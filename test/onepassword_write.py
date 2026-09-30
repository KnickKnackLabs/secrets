"""Fake-only tests for provider-assigned field identities and write verification."""
import copy
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "writer", Path(__file__).resolve().parents[1] / "lib/providers/onepassword/write.py")
writer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(writer)


def note(field_id="provider-generated"):
    return {"id": "item-id", "title": "agent/key", "category": "SECURE_NOTE",
            "vault": {"id": "vault-id"}, "fields": [
                {"id": "notesPlain", "label": "notesPlain", "type": "STRING", "value": "notes"},
                {"id": field_id, "label": "value", "type": "CONCEALED", "value": "old"}]}


class WriterTests(unittest.TestCase):
    def test_update_preserves_provider_id_and_other_fields(self):
        item = note()
        match = {key: item[key] for key in ("id", "title", "vault")}
        payloads = []

        def request(*args, payload=None):
            if args == ("list",):
                return [match]
            if args == ("get", "item-id"):
                return copy.deepcopy(item)
            self.assertEqual(args, ("edit", "item-id"))
            payloads.append(copy.deepcopy(payload))
            return payload

        with patch.object(writer, "request", side_effect=request):
            writer.write("agent/key", "replacement")
        self.assertEqual(payloads[0]["fields"][0], item["fields"][0])
        self.assertEqual(payloads[0]["fields"][1]["id"], "provider-generated")
        self.assertEqual(payloads[0]["fields"][1]["value"], "replacement")

    def test_create_accepts_provider_normalized_id(self):
        result = note("normalized-id")
        result["fields"][1]["value"] = "replacement"
        with patch.object(writer, "request", side_effect=[[], result]) as request:
            writer.write("agent/key", "replacement")
        self.assertEqual(request.call_args.kwargs["payload"]["fields"][0]["id"], "value")

    def test_literal_id_remains_supported(self):
        self.assertEqual(writer.value_field(note("value"))["id"], "value")

    def test_invalid_fields_rejected(self):
        for change in (lambda f: f.update(id=""), lambda f: f.update(id=None),
                       lambda f: f.update(type="STRING"), lambda f: f.update(label="other")):
            item = note()
            change(item["fields"][1])
            with self.subTest(item=item), self.assertRaises(writer.Error):
                writer.value_field(item)
        for field in ({"id": "extra", "label": "value", "type": "CONCEALED"},
                      {"id": "provider-generated", "label": "other", "type": "STRING"},
                      {"id": "value", "label": "other", "type": "CONCEALED"}):
            item = note()
            item["fields"].append(field)
            with self.subTest(field=field), self.assertRaises(writer.Error):
                writer.value_field(item)

    def test_update_response_must_preserve_selected_identity(self):
        item = note("changed-id")
        item["fields"][1]["value"] = "replacement"
        with self.assertRaises(writer.Error):
            writer.verify_write(item, "agent/key", "replacement", "provider-generated")

    def test_response_must_contain_exact_value_and_valid_field(self):
        with self.assertRaises(writer.Error):
            writer.verify_write(note(), "agent/key", "replacement")
        item = note()
        item["fields"][1].update(type="STRING", value="replacement")
        with self.assertRaises(writer.Error):
            writer.verify_write(item, "agent/key", "replacement")


if __name__ == "__main__":
    unittest.main()
