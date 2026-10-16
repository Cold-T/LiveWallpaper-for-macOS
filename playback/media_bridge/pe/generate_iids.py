#!/usr/bin/env python3
"""WinRT pinterface UUIDv5 identities, following the published WinRT signature ABI."""
import sys
import uuid
from pathlib import Path

NS = uuid.UUID("11f47ad5-7b73-42c0-abae-878b1e16adee")
TYPES = {
    "iid_async_manager": ("9fc2b0bb-e446-44e2-aa61-9cab8f636af2", "rc(Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager;{cace8eac-e86e-504a-ab31-5ff8ff1bce49})"),
    "iid_async_properties": ("9fc2b0bb-e446-44e2-aa61-9cab8f636af2", "rc(Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties;{68856cf6-adb4-54b2-ac16-05837907acb6})"),
    "iid_async_bool": ("9fc2b0bb-e446-44e2-aa61-9cab8f636af2", "b1"),
    "iid_vector": ("bbe1fa4c-b0e3-4583-baef-1f1b2e483e56", "rc(Windows.Media.Control.GlobalSystemMediaTransportControlsSession;{7148c835-9b14-5ae2-ab85-dc9b1c14e1a8})"),
    "iid_session_iterable": ("faa585ea-6214-4217-afda-7f46de5869b3", "rc(Windows.Media.Control.GlobalSystemMediaTransportControlsSession;{7148c835-9b14-5ae2-ab85-dc9b1c14e1a8})"),
    "iid_session_iterator": ("6a79e863-4300-459a-9966-cbb660963ee1", "rc(Windows.Media.Control.GlobalSystemMediaTransportControlsSession;{7148c835-9b14-5ae2-ab85-dc9b1c14e1a8})"),
    "iid_string_vector": ("bbe1fa4c-b0e3-4583-baef-1f1b2e483e56", "string"),
    "iid_string_iterable": ("faa585ea-6214-4217-afda-7f46de5869b3", "string"),
    "iid_string_iterator": ("6a79e863-4300-459a-9966-cbb660963ee1", "string"),
    "iid_async_stream": ("9fc2b0bb-e446-44e2-aa61-9cab8f636af2", "{cc254827-4b3d-438f-9232-10c76bc7e038}"),
    "iid_async_buffer_progress": ("b5d036d7-e297-498f-ba60-0289e76e23dd", "{905a0fe0-bc53-11df-8c49-001e4fc686da};u4"),
    "iid_async_u32": ("9fc2b0bb-e446-44e2-aa61-9cab8f636af2", "u4"),
    "iid_handler_u32": ("fcdcf02c-e5d8-4478-915a-4d90b74b83a5", "u4"),
    "iid_handler_bool": ("fcdcf02c-e5d8-4478-915a-4d90b74b83a5", "b1"),
}
for index, (name, iid) in enumerate((
    ("CurrentSessionChangedEventArgs", "6969cb39-0bfa-5fe0-8d73-09cc5e5408e1"),
    ("SessionsChangedEventArgs", "bbf0cd32-42c4-5a58-b317-f34bbfbd26e0"),
    ("TimelinePropertiesChangedEventArgs", "29033a2f-c923-5a77-bcaf-055ff415ad32"),
    ("PlaybackInfoChangedEventArgs", "786756c2-bc0d-50a5-8807-054291fef139"),
    ("MediaPropertiesChangedEventArgs", "7d3741cb-adf0-5cef-91ba-cfabcdd77678"),
)):
    sender = TYPES["iid_async_manager"][1] if index < 2 else TYPES["iid_vector"][1]
    args = f"rc(Windows.Media.Control.{name};{{{iid}}})"
    TYPES[f"iid_event_handler_{index}"] = ("9de1c534-6ae1-11e0-84e1-18a905bcc53f", sender + ";" + args)
lines = ["/* Generated from WinRT type signatures; do not edit. */"]
for name, (generic, parameter) in TYPES.items():
    value = uuid.uuid5(NS, f"pinterface({{{generic}}};{parameter})")
    a,b,c,*tail = value.fields
    raw=value.bytes
    lines.append(f"static const GUID {name} = {{0x{a:08x},0x{b:04x},0x{c:04x},{{{','.join('0x%02x'%x for x in raw[8:])}}}}}; /* {value} */")
Path(sys.argv[1]).write_text("\n".join(lines)+"\n")
