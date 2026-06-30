import os
import requests

class LinearClient:
    def __init__(self, api_key=None, team_id=None):
        self.api_key = api_key or os.environ.get("LINEAR_API_KEY")
        self.team_id = team_id or os.environ.get("LINEAR_TEAM_ID")
        self.url = "https://api.linear.app/graphql"

    def is_enabled(self):
        return bool(self.api_key and self.team_id)

    def create_issue(self, title, description, priority=0):
        if not self.is_enabled():
            return None

        query = """
        mutation IssueCreate($title: String!, $description: String!, $teamId: String!, $priority: Int!) {
          issueCreate(input: {
            title: $title
            description: $description
            teamId: $teamId
            priority: $priority
          }) {
            success
            issue {
              id
              url
            }
          }
        }
        """
        variables = {
            "title": title,
            "description": description,
            "teamId": self.team_id,
            "priority": priority
        }

        headers = {
            "Content-Type": "application/json",
            "Authorization": self.api_key
        }

        try:
            response = requests.post(self.url, json={"query": query, "variables": variables}, headers=headers)
            response.raise_for_status()
            data = response.json()

            if "errors" in data:
                print(f"Linear API error: {data['errors']}")
                return None

            return data["data"]["issueCreate"]["issue"]
        except Exception as e:
            print(f"Failed to create Linear issue: {e}")
            return None

if __name__ == "__main__":
    client = LinearClient()
    if client.is_enabled():
        print("Linear integration is enabled.")
    else:
        print("Linear integration is disabled (missing API key or Team ID).")
