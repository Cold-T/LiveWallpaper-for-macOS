"""Cross-check generated generic interface IDs against shipped SDK declarations.

These are static ABI checks; no PE/Wine code is executed.
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
SDK = REPO / "build/toolchains/llvm-mingw-20261006-ucrt-macos-universal/generic-w64-mingw32/include"


class WinRTABITests(unittest.TestCase):
    def test_generic_stream_and_callback_identifiers_match_sdk(self):
        if not SDK.exists():
            self.skipTest("optional downloaded cross SDK absent")
        with tempfile.TemporaryDirectory() as directory:
            header = Path(directory)/"iids.h"
            subprocess.run([sys.executable,str(ROOT/"pe/generate_iids.py"),str(header)],check=True)
            generated = header.read_text()
        checks = {
            "iid_async_u32": ("windows.foundation.h","IID___FIAsyncOperation_1_UINT32"),
            "iid_handler_u32": ("windows.foundation.h","IID___FIAsyncOperationCompletedHandler_1_UINT32"),
            "iid_async_stream": ("windows.storage.streams.h","IID___FIAsyncOperation_1_Windows__CStorage__CStreams__CIRandomAccessStreamWithContentType"),
            "iid_async_buffer_progress": ("windows.storage.streams.h","IID___FIAsyncOperationWithProgress_2_Windows__CStorage__CStreams__CIBuffer_UINT32"),
            "iid_handler_bool": ("windows.foundation.h","IID___FIAsyncOperationCompletedHandler_1_boolean"),
        }
        for name,(file,interface) in checks.items():
            values = re.search(rf"{name}\s*=\s*\{{(.*?)\}};",generated,re.S).group(1)
            expected = re.search(rf"DEFINE_GUID\({interface},(.*?)\);",(SDK/file).read_text(),re.S).group(1)
            self.assertEqual(re.findall(r"0x[0-9a-f]+",values),re.findall(r"0x[0-9a-f]+",expected),name)

    def test_event_delegate_ids_match_independent_native_contracts(self):
        # Independent literals recovered from original C++/WinRT handler QI data;
        # do not derive expected IDs from the bridge's own signature constants.
        expected = [
            "228bd0ed-1fa2-5e9b-a6ec-42566173103b",
            "2e2a8630-dc8c-530a-9746-bc984d4b029e",
            "e8bf62af-fac1-5fff-9053-0bf191ae777e",
            "2bdf1426-d41f-5896-897f-efc0b0fa7392",
            "0f2ce2b7-afa7-5ed0-8cb6-8c40cf9b3a5f",
        ]
        with tempfile.TemporaryDirectory() as directory:
            output=Path(directory)/"iids.h"
            subprocess.run([sys.executable,str(ROOT/"pe/generate_iids.py"),str(output)],check=True)
            generated=output.read_text()
        found=re.findall(r"iid_event_handler_\d.*?/\* ([0-9a-f-]+) \*/",generated)
        self.assertEqual(found,expected)
        probe=(ROOT/"pe/probe-contracts.inc").read_text()
        self.assertNotIn("&iid_event_handler_",probe)

    def test_datareader_vtable_has_official_order(self):
        # Independent ordered method list from Microsoft's IDataReader_Vtbl.
        names=["dr_unconsumed","dr_encoding","dr_put_encoding","dr_order","dr_put_order",
               "dr_options","dr_put_options","dr_read_byte","dr_read_bytes","dr_read_buffer",
               "dr_read_bool","dr_read_guid","dr_read_i16","dr_read_i32","dr_read_i64",
               "dr_read_u16","dr_read_u32","dr_read_u64","dr_read_float","dr_read_double",
               "dr_read_string","dr_read_i64","dr_read_i64","dr_load","dr_detach_buffer","dr_detach_stream"]
        text=(ROOT/"pe/datareader-vtables.inc").read_text()
        table=re.search(r"dr_vt_reader\[\]=\{(.*?)\};",text).group(1)
        self.assertEqual(re.findall(r"T\((\w+)\)",table),names)
        self.assertEqual(6+names.index("dr_load"),29)
        self.assertEqual(6+names.index("dr_read_bytes"),14)

    def test_vtables_only_use_traced_methods(self):
        text=(ROOT/"pe/lwmedia-winrt.c").read_text()
        for table,methods in re.findall(r"static const void \*([^\[]+)\[\]\s*=\s*\{(.*?)\};",text,re.S):
            stripped=re.sub(r"T\(\w+\)|BASE|FACET_BASE|[\s,]","",methods)
            self.assertEqual(stripped,"",table)


if __name__ == "__main__":
    unittest.main()
