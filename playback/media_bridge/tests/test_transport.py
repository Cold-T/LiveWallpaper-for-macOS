import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import base64
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("media_broker", ROOT / "broker.py")
broker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(broker)


class TransportTests(unittest.TestCase):
    def test_fixture_provenance_and_unicode(self):
        value = json.loads((ROOT / "tests/snapshot-fixture.json").read_text())
        data, info = broker.pack_snapshot(value, 17, fixture=True)
        header = broker.HEADER.unpack_from(data)
        self.assertEqual(len(data), broker.SIZE)
        self.assertEqual(header[0], broker.MAGIC)
        self.assertEqual(header[3:6], (17, 3, 4))
        self.assertTrue(info["fixture"])
        title_offset = broker.HEADER.size + 128*2
        title = data[title_offset:title_offset+512*2].decode("utf-16-le").split("\0", 1)[0]
        self.assertEqual(title, value["title"])
        self.assertEqual(header[7], 122500000)

    def test_surrogate_boundary_and_no_media(self):
        self.assertEqual(broker.utf16("A🎵", 3).decode("utf-16-le"), "A\0\0")
        data, _ = broker.pack_snapshot({"available":False,"reason":"permission_required"},1)
        self.assertEqual(broker.HEADER.unpack_from(data)[4] & 1, 0)

    def test_atomic_publish(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)/"session.bin"
            broker.publish(output, {"bundleIdentifier":"fixture.one"}, 1, True)
            broker.publish(output, {"available":False}, 2, True)
            self.assertEqual(output.stat().st_size, broker.SIZE)
            self.assertEqual(broker.HEADER.unpack_from(output.read_bytes())[3], 2)
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            self.assertEqual(output.with_suffix(".bin.json").stat().st_mode & 0o777, 0o600)

    def test_artwork_bytes_generation_and_unknown(self):
        with tempfile.TemporaryDirectory() as directory:
            output=Path(directory)/"session.bin"
            image=b"\x89PNG\r\n\x1a\nfixture-only-bytes"
            broker.publish(output,{"bundleIdentifier":"fixture.art","artworkBase64":base64.b64encode(image).decode()},3,True)
            art=Path(str(output)+".art").read_bytes()
            self.assertEqual(broker.ART_HEADER.unpack_from(art),(b"LWMART01",1,3,2,len(image)))
            self.assertEqual(art[broker.ART_HEADER.size:],image)
            broker.publish(output,{"bundleIdentifier":"fixture.art"},4,True)
            self.assertEqual(broker.ART_HEADER.unpack(Path(str(output)+".art").read_bytes()),(b"LWMART01",1,4,0,0))

    def make_request(self,directory,command=3,target="com.spotify.client"):
        path=Path(directory)/(str(uuid.uuid4())+".req")
        path.write_bytes(broker.COMMAND.pack(b"LWMCMD01",1,command,0,broker.utf16(target,128)))
        return path.with_suffix(".ack")

    def test_fixture_commands_are_denied_without_runner(self):
        with tempfile.TemporaryDirectory() as directory:
            ack=self.make_request(directory)
            broker.handle_requests(directory,None,None,True,runner=lambda *a,**k:self.fail("fixture sent command"))
            record=broker.ACK.unpack(ack.read_bytes())
            self.assertEqual(record,(b"LWMACK01",1,0,0x80070005,2))

    def test_native_transport_routes_and_does_not_replay(self):
        with tempfile.TemporaryDirectory() as directory:
            ack=self.make_request(directory)
            calls=[]
            def fake_runner(args,**kwargs):
                calls.append(args)
                return subprocess.CompletedProcess(args,0,'{"ok":true}')
            broker.handle_requests(directory,"spotify",Path("fixture-helper"),False,runner=fake_runner)
            self.assertEqual(broker.ACK.unpack(ack.read_bytes()),(b"LWMACK01",1,1,0,0))
            self.assertEqual(calls[0][1:],["--command","next","--player","spotify","--allow-automation"])
            broker.handle_requests(directory,"spotify",Path("fixture-helper"),False,runner=fake_runner)
            self.assertEqual(len(calls),1)

    def test_ambiguous_command_failure_never_retries(self):
        with tempfile.TemporaryDirectory() as directory:
            ack=self.make_request(directory)
            calls=[]
            def fake_runner(args,**kwargs):
                calls.append(args)
                raise subprocess.TimeoutExpired(args,1)
            for _ in range(2):
                broker.handle_requests(directory,"spotify",Path("fixture-helper"),False,runner=fake_runner)
            self.assertEqual(len(calls),1)
            self.assertEqual(broker.ACK.unpack(ack.read_bytes())[2:4],(0,0x80004005))

    def test_wrong_player_is_denied(self):
        with tempfile.TemporaryDirectory() as directory:
            ack=self.make_request(directory,target="com.apple.Music")
            broker.handle_requests(directory,"spotify",Path("fixture-helper"),False,runner=lambda *a,**k:self.fail("wrong target sent"))
            self.assertEqual(broker.ACK.unpack(ack.read_bytes())[2],0)

    def test_https_artwork_fetch_is_bounded_cached_and_optional(self):
        image=b"\x89PNG\r\n\x1a\nfixture-only-bytes"
        calls=[]
        class Response:
            def __enter__(self):return self
            def __exit__(self,*args):return False
            def geturl(self):return "https://fixture.invalid/art.png"
            def read(self,limit):
                self_limit=broker.MAX_ART+1
                if limit!=self_limit:raise AssertionError(limit)
                return image
        def fake_opener(request,**kwargs):
            calls.append(request.full_url)
            return Response()
        cache={}
        for _ in range(2):
            payload={"session":{"bundleIdentifier":"fixture.art","artworkURL":"https://fixture.invalid/art.png"}}
            result=broker.fetch_artwork(payload,cache,opener=fake_opener)
            self.assertEqual(base64.b64decode(result["session"]["artworkBase64"]),image)
        self.assertEqual(len(calls),1)
        broker.fetch_artwork({"artworkURL":"http://fixture.invalid/art.png"},{},opener=lambda *a,**k:self.fail("non-HTTPS fetch"))

    def test_artwork_history_is_bounded(self):
        with tempfile.TemporaryDirectory() as directory:
            output=Path(directory)/"state.bin"
            for generation in range(12):
                broker.publish(output,{"bundleIdentifier":"fixture.history"},generation,True)
            self.assertLessEqual(len(list(Path(directory).glob("state.bin.art.[0-9]*"))),8)


if __name__ == "__main__":
    unittest.main()
