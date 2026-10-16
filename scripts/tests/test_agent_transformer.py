import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch


spec = importlib.util.spec_from_file_location(
    "agent_transformer",
    Path(__file__).resolve().parents[1] / "helpers" / "agent-transformer.py",
)
transformer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transformer)


class AgentTransformerTests(unittest.TestCase):
    def test_json_transformation_needs_no_yaml_and_preserves_unicode(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.json"
            target = Path(directory) / "target.json"
            source.write_text(
                json.dumps({
                    "name": "agent",
                    "model": "my-deployment",
                    "instructions": "Snowman: \u2603",
                }, ensure_ascii=False),
                encoding="utf-8-sig",
            )
            with patch.dict("sys.modules", {"yaml": None}):
                self.assertTrue(transformer.transform_agent_config(str(source), str(target)))
            config = json.loads(target.read_text(encoding="utf-8"))
            self.assertEqual(config["systemPrompt"]["template"], "Snowman: \u2603")
            self.assertEqual(config["modelConfiguration"]["modelDeployment"], "my-deployment")
            self.assertNotIn("temperature", config["modelConfiguration"])

    def test_json_to_yaml_loads_optional_yaml_module_at_output(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.json"
            target = Path(directory) / "target.yaml"
            source.write_text('{"name": "agent", "model": "my-deployment"}', encoding="utf-8")
            yaml = Mock()
            with patch.dict("sys.modules", {"yaml": yaml}):
                self.assertTrue(transformer.transform_agent_config(str(source), str(target)))
            yaml.dump.assert_called_once()
            self.assertEqual(yaml.dump.call_args.args[0]["metadata"]["name"], "agent")


if __name__ == "__main__":
    unittest.main()
