"""
Example Foundry Agent: Energy Analysis Assistant
Transformed from OpenAI Studio deployment

This agent provides energy consumption analysis and recommendations
for operational needs.
"""

import os
import json
import logging
from typing import Optional
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import MessageRole

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class EnergyAnalysisAgent:
    """
    Energy Analysis Agent - migrated from OpenAI Studio
    
    Capabilities:
    - Analyze energy consumption patterns
    - Provide cost optimization recommendations
    - Forecast energy demand
    - Generate compliance reports
    """
    
    def __init__(self):
        """Initialize the agent with Foundry resources."""
        self.project_endpoint = os.getenv("AZURE_AI_PROJECT_ENDPOINT")
        self.credential = DefaultAzureCredential()
        self.client = AIProjectClient(
            uri=self.project_endpoint,
            credential=self.credential
        )
        self.agent_name = "energy-analysis-assistant"
        self.model_deployment = os.getenv(
            "AGENT_ENERGY_ANALYSIS_ASSISTANT_DEPLOYMENT",
            "gpt-4o-deployment"
        )
        
    def get_system_prompt(self) -> str:
        """Get the system prompt with governance directives."""
        base_prompt = """You are an Energy Analysis Assistant. 
Your role is to:

1. ANALYZE energy consumption data and patterns
   - Identify peak usage periods
   - Detect anomalies and inefficiencies
   - Compare to industry benchmarks

2. PROVIDE recommendations for:
   - Cost optimization and savings opportunities
   - Energy efficiency improvements
   - Compliance with regulations
   - Risk mitigation strategies

3. FORECAST and PREDICT:
   - Future energy demand
   - Seasonal variations
   - Impact of operational changes

4. GENERATE reports including:
   - Executive summaries
   - Detailed analysis
   - Actionable recommendations
   - Risk assessments

Be precise, professional, and data-driven in your analysis.
Always cite data sources and assumptions."""

        governance = """

GOVERNANCE DIRECTIVES:
- Comply with content policies and guardrails
- Redact PII (personal identifiable information) in all outputs
- Log all interactions for audit compliance
- Respect data residency requirements
- Apply least-privilege access to sensitive data
- Maintain confidentiality of proprietary operational data
"""
        return base_prompt + governance
    
    def invoke(self, user_message: str, context: Optional[dict] = None) -> dict:
        """
        Invoke the agent with a user message.
        
        Args:
            user_message: User's query or request
            context: Optional context (e.g., historical data, parameters)
        
        Returns:
            Agent response with analysis
        """
        logger.info(f"Invoking agent with message: {user_message[:100]}...")
        
        try:
            # Prepare context if provided
            if context:
                user_message = self._format_with_context(user_message, context)
            
            # Invoke the agent
            messages = [
                {
                    "role": MessageRole.USER,
                    "content": user_message
                }
            ]
            
            response = self.client.agents.chat(
                agent_id=self.agent_name,
                messages=messages,
                model_deployment=self.model_deployment,
                max_tokens=2048,
                temperature=0.7,
                top_p=0.9
            )
            
            logger.info("Agent invocation successful")
            return {
                "status": "success",
                "response": response,
                "model_used": self.model_deployment
            }
            
        except Exception as e:
            logger.error(f"Agent invocation failed: {e}")
            return {
                "status": "error",
                "error": str(e),
                "model_used": self.model_deployment
            }
    
    def analyze_consumption(
        self,
        consumption_data: dict,
        period: str = "monthly"
    ) -> dict:
        """
        Analyze energy consumption data.
        
        Args:
            consumption_data: Energy consumption metrics
            period: Analysis period (hourly, daily, monthly, yearly)
        
        Returns:
            Analysis results with insights and recommendations
        """
        analysis_prompt = f"""
Analyze the following {period} energy consumption data:

{json.dumps(consumption_data, indent=2)}

Provide:
1. Summary statistics and trends
2. Identified anomalies or concerns
3. Top 3 cost optimization opportunities
4. Recommended actions with estimated savings
5. Regulatory compliance assessment
"""
        
        return self.invoke(analysis_prompt, context=consumption_data)
    
    def forecast_demand(
        self,
        historical_data: dict,
        forecast_period: str = "next_quarter"
    ) -> dict:
        """
        Forecast future energy demand.
        
        Args:
            historical_data: Historical consumption data
            forecast_period: Period to forecast (next_month, next_quarter, next_year)
        
        Returns:
            Demand forecast with confidence intervals
        """
        forecast_prompt = f"""
Based on the following historical energy data, forecast demand for the {forecast_period}:

{json.dumps(historical_data, indent=2)}

Provide:
1. Demand forecast with confidence intervals
2. Expected peak consumption periods
3. Seasonal adjustments
4. Key factors influencing forecast
5. Recommendations for capacity planning
"""
        
        return self.invoke(forecast_prompt, context=historical_data)
    
    @staticmethod
    def _format_with_context(message: str, context: dict) -> str:
        """Format message with additional context."""
        context_str = json.dumps(context, indent=2)
        return f"{message}\n\nContext:\n{context_str}"


# Example usage
if __name__ == "__main__":
    agent = EnergyAnalysisAgent()
    
    # Example 1: General analysis request
    print("Example 1: General Analysis")
    print("=" * 50)
    response = agent.invoke(
        "What are the typical energy consumption patterns in the utility industry?"
    )
    print(f"Response: {response}")
    print()
    
    # Example 2: Consumption analysis
    print("Example 2: Consumption Analysis")
    print("=" * 50)
    sample_data = {
        "facility": "TX-Station-01",
        "period": "2024-Q3",
        "total_consumption_kwh": 125000,
        "peak_usage_kw": 450,
        "average_usage_kw": 350,
        "off_peak_percentage": 35
    }
    response = agent.analyze_consumption(sample_data)
    print(f"Response: {response}")
    print()
    
    # Example 3: Demand forecasting
    print("Example 3: Demand Forecasting")
    print("=" * 50)
    historical_data = {
        "last_12_months": [
            {"month": "Jan", "consumption_kwh": 110000},
            {"month": "Feb", "consumption_kwh": 115000},
            # ... more months
            {"month": "Sep", "consumption_kwh": 125000},
        ]
    }
    response = agent.forecast_demand(historical_data)
    print(f"Response: {response}")
