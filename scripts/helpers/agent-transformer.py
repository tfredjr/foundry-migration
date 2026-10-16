#!/usr/bin/env python3
"""
Agent Transformer: Converts OpenAI Studio agents to Azure Foundry agents.
Handles prompt refactoring, tool migration, and configuration mapping.
"""

import json
import sys
from pathlib import Path
from typing import Dict, List, Any, Optional
from datetime import datetime
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s'
)
logger = logging.getLogger(__name__)


class AgentTransformer:
    """Transform OpenAI Studio agents to Foundry agents."""
    
    def __init__(self, source_config: Dict[str, Any]):
        self.source = source_config
        self.target = {}
        
    def transform(self) -> Dict[str, Any]:
        """Execute complete transformation."""
        logger.info(f"Transforming agent: {self.source.get('name', 'unknown')}")
        
        # Transform metadata
        self._transform_metadata()
        
        # Transform model configuration
        self._transform_model_config()
        
        # Transform system prompt
        self._transform_system_prompt()
        
        # Transform tools
        self._transform_tools()
        
        # Add governance directives
        self._add_governance_directives()
        
        logger.info(f"Transformation complete: {self.target.get('name')}")
        return self.target
    
    def _transform_metadata(self):
        """Transform basic metadata."""
        self.target['metadata'] = {
            'name': self.source.get('name', 'migrated-agent'),
            'description': self.source.get('description', ''),
            'owner': self.source.get('owner', 'unknown'),
            'createdFrom': self.source.get('id', 'unknown'),
            'createdDate': datetime.utcnow().isoformat() + 'Z',
            'version': '1.0.0',
            'tags': self.source.get('tags', ['migrated'])
        }
    
    def _transform_model_config(self):
        """Transform model configuration from OpenAI to Foundry."""
        source_model = self.source['model']
        
        self.target['modelConfiguration'] = {
            'modelDeployment': self.source.get('model_deployment', source_model),
            'modelVersion': self.source.get('model_version', 'unspecified'),
            'fallbackModels': []
        }
        for source_key, target_key in (
            ('temperature', 'temperature'),
            ('max_tokens', 'maxTokens'),
            ('top_p', 'topP'),
        ):
            if source_key in self.source:
                self.target['modelConfiguration'][target_key] = self.source[source_key]
    
    def _transform_system_prompt(self):
        """Transform and enhance system prompt with governance directives."""
        base_prompt = self.source.get('system_prompt') or self.source.get('instructions', '')
        
        self.target['systemPrompt'] = {
            'template': base_prompt,
            'governanceInstructions': self._get_governance_suffix()
        }
    
    def _transform_tools(self):
        """Transform function calls and tools to Foundry format."""
        tools = self.source.get('tools', [])
        if not isinstance(tools, list) or any(not isinstance(tool, dict) for tool in tools):
            raise ValueError("tools must be a list of tool definitions")
        self.target['tools'] = tools
    
    def _add_governance_directives(self):
        """Add governance configuration."""
        self.target['governance'] = {
            'guardrails': [
                'jailbreak-detection',
                'pii-detection',
                'hate-speech-filter',
                'content-filter'
            ],
            'auditLogging': True,
            'requiredRoles': ['agent-developer', 'agent-operator'],
            'dataResidency': 'us',
            'complianceFrameworks': ['soc2']
        }
        
        self.target['deployment'] = {
            'targetEnvironment': 'dev',
            'replicas': 1,
            'maxConcurrentRequests': 100,
            'timeoutSeconds': 30,
            'healthCheckInterval': 30
        }
        
        self.target['monitoring'] = {
            'enableTracing': True,
            'enableMetrics': True,
            'logLevel': 'INFO',
            'customMetrics': ['invocation-count', 'latency', 'errors']
        }
    
    @staticmethod
    def _get_governance_suffix() -> str:
        """Return standard governance directives to append to prompts."""
        return """

---
GOVERNANCE DIRECTIVES (DO NOT MODIFY):
1. You must comply with all content policies and guardrails.
2. Do not attempt to bypass safety features or jailbreak detection.
3. Redact Personally Identifiable Information (PII) in responses.
4. All interactions are logged for audit and compliance purposes.
5. Follow the principle of least privilege in data access.
6. Respect user privacy and data residency requirements.
"""


def transform_agent_config(
    input_file: str,
    output_file: str,
    config_override: Optional[Dict[str, Any]] = None
) -> bool:
    """
    Transform a single agent configuration file.
    
    Args:
        input_file: Path to OpenAI agent config (JSON/YAML)
        output_file: Path to write Foundry agent config
        config_override: Optional overrides to apply
    
    Returns:
        True if successful, False otherwise
    """
    try:
        # Load source configuration
        input_path = Path(input_file)
        if input_path.suffix.lower() == '.json':
            with open(input_path, 'r', encoding='utf-8-sig') as f:
                source_config = json.load(f)
        elif input_path.suffix.lower() in ['.yaml', '.yml']:
            import yaml

            with open(input_path, 'r', encoding='utf-8-sig') as f:
                source_config = yaml.safe_load(f)
        else:
            logger.error(f"Unsupported file format: {input_path.suffix}")
            return False
        
        # Apply overrides if provided
        if config_override:
            source_config.update(config_override)
        
        # Transform
        transformer = AgentTransformer(source_config)
        target_config = transformer.transform()
        
        # Save transformed config
        output_path = Path(output_file)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(output_path, 'w', encoding='utf-8') as f:
            if output_path.suffix.lower() == '.json':
                json.dump(target_config, f, indent=2)
            else:
                import yaml

                yaml.dump(target_config, f, default_flow_style=False)
        
        logger.info(f"Saved transformed config: {output_path}")
        return True
        
    except Exception as e:
        logger.error(f"Transformation failed: {e}")
        return False


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: agent-transformer.py <input_file> <output_file> [overrides_json]")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    overrides = json.loads(sys.argv[3]) if len(sys.argv) > 3 else None
    
    success = transform_agent_config(input_file, output_file, overrides)
    sys.exit(0 if success else 1)
