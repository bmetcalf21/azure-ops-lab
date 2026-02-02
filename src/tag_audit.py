#!/usr/bin/env python3
"""
Azure Resource Tag Compliance Auditor

This script audits Azure resources for required governance tags and generates
a compliance report. It uses Azure SDK with DefaultAzureCredential for authentication.

Required tags:
- environment: Deployment stage (lab, dev, prod)
- owner: Responsible party
- project: Cost allocation identifier

Author: Brandon Metcalf
Project: azure-ops-lab
"""

import argparse
import json
import csv
import sys
from typing import List, Dict, Any
from datetime import datetime

try:
    from azure.identity import DefaultAzureCredential
    from azure.mgmt.resource import ResourceManagementClient
    from azure.core.exceptions import AzureError
except ImportError as e:
    print(f"Error: Required Azure SDK libraries not installed.", file=sys.stderr)
    print("Install with: pip install azure-identity azure-mgmt-resource", file=sys.stderr)
    sys.exit(1)


class TagAuditor:
    """Audits Azure resources for tag compliance."""

    REQUIRED_TAGS = ['environment', 'owner', 'project']

    def __init__(self, subscription_id: str, resource_group: str = None):
        """
        Initialize the auditor.

        Args:
            subscription_id: Azure subscription ID
            resource_group: Optional resource group to scope the audit
        """
        self.subscription_id = subscription_id
        self.resource_group = resource_group
        self.credential = None
        self.client = None

    def authenticate(self) -> bool:
        """
        Authenticate to Azure using DefaultAzureCredential.

        Returns:
            bool: True if authentication successful, False otherwise
        """
        try:
            self.credential = DefaultAzureCredential()
            self.client = ResourceManagementClient(
                credential=self.credential,
                subscription_id=self.subscription_id
            )
            # Test authentication by listing resource groups
            _ = list(self.client.resource_groups.list())
            print("Authentication successful.", file=sys.stderr)
            return True
        except AzureError as e:
            print(f"Authentication failed: {e}", file=sys.stderr)
            return False
        except Exception as e:
            print(f"Unexpected error during authentication: {e}", file=sys.stderr)
            return False

    def get_resources(self) -> List[Any]:
        """
        Retrieve resources from Azure.

        Returns:
            List of Azure resource objects
        """
        try:
            if self.resource_group:
                print(f"Scanning resources in resource group: {self.resource_group}", file=sys.stderr)
                resources = list(self.client.resources.list_by_resource_group(
                    self.resource_group
                ))
            else:
                print("Scanning all resources in subscription", file=sys.stderr)
                resources = list(self.client.resources.list())

            print(f"Found {len(resources)} resources to audit.", file=sys.stderr)
            return resources
        except AzureError as e:
            print(f"Error retrieving resources: {e}", file=sys.stderr)
            return []

    def audit_resource(self, resource: Any) -> Dict[str, Any]:
        """
        Audit a single resource for tag compliance.

        Args:
            resource: Azure resource object

        Returns:
            Dictionary containing audit results
        """
        resource_tags = resource.tags if resource.tags else {}
        missing_tags = [tag for tag in self.REQUIRED_TAGS if tag not in resource_tags]

        audit_result = {
            'resource_name': resource.name,
            'resource_type': resource.type,
            'resource_group': resource.id.split('/')[4] if '/' in resource.id else 'unknown',
            'location': resource.location,
            'tags': resource_tags,
            'missing_tags': missing_tags,
            'compliant': len(missing_tags) == 0,
            'compliance_percentage': int(((len(self.REQUIRED_TAGS) - len(missing_tags)) / len(self.REQUIRED_TAGS)) * 100)
        }

        return audit_result

    def run_audit(self) -> List[Dict[str, Any]]:
        """
        Run the complete audit process.

        Returns:
            List of audit results
        """
        if not self.authenticate():
            print("Cannot proceed without authentication.", file=sys.stderr)
            return []

        resources = self.get_resources()
        if not resources:
            print("No resources found to audit.", file=sys.stderr)
            return []

        audit_results = []
        for resource in resources:
            result = self.audit_resource(resource)
            audit_results.append(result)

        return audit_results

    @staticmethod
    def generate_summary(audit_results: List[Dict[str, Any]]) -> Dict[str, Any]:
        """
        Generate summary statistics from audit results.

        Args:
            audit_results: List of audit result dictionaries

        Returns:
            Dictionary containing summary statistics
        """
        total_resources = len(audit_results)
        compliant_resources = sum(1 for r in audit_results if r['compliant'])
        non_compliant_resources = total_resources - compliant_resources

        summary = {
            'audit_timestamp': datetime.utcnow().isoformat() + 'Z',
            'total_resources': total_resources,
            'compliant_resources': compliant_resources,
            'non_compliant_resources': non_compliant_resources,
            'compliance_rate': round((compliant_resources / total_resources * 100), 2) if total_resources > 0 else 0,
            'required_tags': TagAuditor.REQUIRED_TAGS
        }

        return summary


def output_json(audit_results: List[Dict[str, Any]], summary: Dict[str, Any]) -> None:
    """Output results in JSON format."""
    output = {
        'summary': summary,
        'results': audit_results
    }
    print(json.dumps(output, indent=2))


def output_csv(audit_results: List[Dict[str, Any]], summary: Dict[str, Any]) -> None:
    """Output results in CSV format."""
    # Print summary as comments
    print(f"# Audit Timestamp: {summary['audit_timestamp']}")
    print(f"# Total Resources: {summary['total_resources']}")
    print(f"# Compliant: {summary['compliant_resources']}")
    print(f"# Non-Compliant: {summary['non_compliant_resources']}")
    print(f"# Compliance Rate: {summary['compliance_rate']}%")
    print()

    # Write CSV
    if audit_results:
        fieldnames = ['resource_name', 'resource_type', 'resource_group', 'location',
                      'compliant', 'compliance_percentage', 'missing_tags']
        writer = csv.DictWriter(sys.stdout, fieldnames=fieldnames)
        writer.writeheader()

        for result in audit_results:
            csv_row = {
                'resource_name': result['resource_name'],
                'resource_type': result['resource_type'],
                'resource_group': result['resource_group'],
                'location': result['location'],
                'compliant': result['compliant'],
                'compliance_percentage': result['compliance_percentage'],
                'missing_tags': ', '.join(result['missing_tags']) if result['missing_tags'] else 'none'
            }
            writer.writerow(csv_row)


def output_text(audit_results: List[Dict[str, Any]], summary: Dict[str, Any]) -> None:
    """Output results in human-readable text format."""
    print("=" * 80)
    print("AZURE RESOURCE TAG COMPLIANCE AUDIT REPORT")
    print("=" * 80)
    print(f"\nAudit Timestamp: {summary['audit_timestamp']}")
    print(f"Required Tags: {', '.join(summary['required_tags'])}")
    print(f"\nSummary:")
    print(f"  Total Resources: {summary['total_resources']}")
    print(f"  Compliant: {summary['compliant_resources']}")
    print(f"  Non-Compliant: {summary['non_compliant_resources']}")
    print(f"  Compliance Rate: {summary['compliance_rate']}%")
    print("\n" + "=" * 80)

    if summary['non_compliant_resources'] > 0:
        print("\nNON-COMPLIANT RESOURCES:")
        print("-" * 80)
        for result in audit_results:
            if not result['compliant']:
                print(f"\nResource: {result['resource_name']}")
                print(f"  Type: {result['resource_type']}")
                print(f"  Resource Group: {result['resource_group']}")
                print(f"  Missing Tags: {', '.join(result['missing_tags'])}")
                print(f"  Compliance: {result['compliance_percentage']}%")

    print("\n" + "=" * 80)
    print(f"Audit complete. {summary['compliance_rate']}% compliant.")
    print("=" * 80)


def main():
    """Main entry point for the script."""
    parser = argparse.ArgumentParser(
        description='Audit Azure resources for tag compliance',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Audit all resources in subscription (JSON output)
  python tag_audit.py --subscription-id abc123 --output-format json

  # Audit specific resource group (CSV output)
  python tag_audit.py --subscription-id abc123 --resource-group my-rg --output-format csv

  # Human-readable output
  python tag_audit.py --subscription-id abc123 --output-format text

Authentication:
  This script uses DefaultAzureCredential, which attempts authentication in this order:
  1. Environment variables (AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET)
  2. Managed Identity (if running in Azure)
  3. Azure CLI credentials (az login)
  4. Visual Studio Code credentials
  5. Azure PowerShell credentials

Required Tags:
  - environment: Deployment stage (lab, dev, prod)
  - owner: Responsible party
  - project: Cost allocation identifier
        """
    )

    parser.add_argument(
        '--subscription-id',
        required=True,
        help='Azure subscription ID'
    )
    parser.add_argument(
        '--resource-group',
        help='Optional: Resource group to scope the audit (default: all resources)'
    )
    parser.add_argument(
        '--output-format',
        choices=['json', 'csv', 'text'],
        default='text',
        help='Output format (default: text)'
    )

    args = parser.parse_args()

    # Run audit
    auditor = TagAuditor(
        subscription_id=args.subscription_id,
        resource_group=args.resource_group
    )

    audit_results = auditor.run_audit()
    if not audit_results:
        print("Audit failed or no resources found.", file=sys.stderr)
        sys.exit(1)

    summary = auditor.generate_summary(audit_results)

    # Output results in requested format
    if args.output_format == 'json':
        output_json(audit_results, summary)
    elif args.output_format == 'csv':
        output_csv(audit_results, summary)
    else:
        output_text(audit_results, summary)

    # Exit with non-zero status if compliance is not 100%
    if summary['compliance_rate'] < 100:
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == '__main__':
    main()
