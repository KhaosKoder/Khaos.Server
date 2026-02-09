# Use Case: Staff Productivity Analysis with Azure DevOps

> How to use Khaos Server to analyze team productivity using Azure DevOps data

---

## Overview

This use case demonstrates how to:
1. Connect to Azure DevOps REST API
2. Extract work items, commits, and PRs per developer
3. Store data in Redis for fast access
4. Use AI to analyze patterns and identify issues
5. Generate productivity insights

---

## Step 1: Set Up Azure DevOps Access

### Get a Personal Access Token (PAT)

1. Go to Azure DevOps → User Settings → Personal Access Tokens
2. Create a new token with scopes:
   - `Work Items (Read)`
   - `Code (Read)`
   - `Graph (Read)` - for team member info

### Store credentials in Redis

```bash
# Via WSL command line:
redis-cli SET azure:org "your-organization"
redis-cli SET azure:project "your-project"
redis-cli SET azure:pat "your-personal-access-token"
```

Or via the Redis Manager UI at http://localhost:3000/redis

---

## Step 2: Create the Data Extraction API

Add these endpoints to `/opt/khaos/apps/api/Program.cs`:

```csharp
// ============================================================================
// Azure DevOps Integration
// ============================================================================

// Configure Azure DevOps HttpClient
builder.Services.AddHttpClient("AzureDevOps", (sp, client) =>
{
    var redis = sp.GetRequiredService<IConnectionMultiplexer>().GetDatabase();
    var org = redis.StringGet("azure:org").ToString();
    var pat = redis.StringGet("azure:pat").ToString();
    
    client.BaseAddress = new Uri($"https://dev.azure.com/{org}/");
    var credentials = Convert.ToBase64String(System.Text.Encoding.ASCII.GetBytes($":{pat}"));
    client.DefaultRequestHeaders.Authorization = 
        new System.Net.Http.Headers.AuthenticationHeaderValue("Basic", credentials);
});

// Get team members
app.MapGet("/api/devops/team", async (IConnectionMultiplexer redis, IHttpClientFactory httpFactory) =>
{
    var db = redis.GetDatabase();
    var project = db.StringGet("azure:project").ToString();
    var client = httpFactory.CreateClient("AzureDevOps");
    
    var response = await client.GetFromJsonAsync<JsonElement>($"{project}/_apis/wit/wiql?api-version=7.0");
    // Extract unique assignees from work items
    
    return Results.Ok(response);
});

// Get work items by user (last 30 days)
app.MapGet("/api/devops/workitems/{email}", async (
    string email, 
    IConnectionMultiplexer redis, 
    IHttpClientFactory httpFactory) =>
{
    var db = redis.GetDatabase();
    var project = db.StringGet("azure:project").ToString();
    var client = httpFactory.CreateClient("AzureDevOps");
    
    var wiql = new
    {
        query = $@"
            SELECT [System.Id], [System.Title], [System.State], [System.CreatedDate], [System.ChangedDate]
            FROM WorkItems
            WHERE [System.AssignedTo] = '{email}'
            AND [System.ChangedDate] >= @Today - 30
            ORDER BY [System.ChangedDate] DESC"
    };
    
    var response = await client.PostAsJsonAsync($"{project}/_apis/wit/wiql?api-version=7.0", wiql);
    var result = await response.Content.ReadFromJsonAsync<JsonElement>();
    
    // Get work item details
    if (result.TryGetProperty("workItems", out var items))
    {
        var ids = items.EnumerateArray().Select(i => i.GetProperty("id").GetInt32()).Take(100);
        if (ids.Any())
        {
            var details = await client.GetFromJsonAsync<JsonElement>(
                $"{project}/_apis/wit/workitems?ids={string.Join(",", ids)}&api-version=7.0");
            return Results.Ok(details);
        }
    }
    
    return Results.Ok(new { workItems = Array.Empty<object>() });
});

// Get commits by user (last 30 days)
app.MapGet("/api/devops/commits/{email}", async (
    string email,
    IConnectionMultiplexer redis,
    IHttpClientFactory httpFactory) =>
{
    var db = redis.GetDatabase();
    var project = db.StringGet("azure:project").ToString();
    var client = httpFactory.CreateClient("AzureDevOps");
    
    var fromDate = DateTime.UtcNow.AddDays(-30).ToString("yyyy-MM-dd");
    var response = await client.GetFromJsonAsync<JsonElement>(
        $"{project}/_apis/git/repositories?api-version=7.0");
    
    var allCommits = new List<JsonElement>();
    
    if (response.TryGetProperty("value", out var repos))
    {
        foreach (var repo in repos.EnumerateArray())
        {
            var repoId = repo.GetProperty("id").GetString();
            var commits = await client.GetFromJsonAsync<JsonElement>(
                $"{project}/_apis/git/repositories/{repoId}/commits?" +
                $"searchCriteria.author={email}&searchCriteria.fromDate={fromDate}&api-version=7.0");
            
            if (commits.TryGetProperty("value", out var commitList))
            {
                allCommits.AddRange(commitList.EnumerateArray());
            }
        }
    }
    
    return Results.Ok(new { count = allCommits.Count, commits = allCommits });
});

// Get pull requests by user
app.MapGet("/api/devops/pullrequests/{email}", async (
    string email,
    IConnectionMultiplexer redis,
    IHttpClientFactory httpFactory) =>
{
    var db = redis.GetDatabase();
    var project = db.StringGet("azure:project").ToString();
    var client = httpFactory.CreateClient("AzureDevOps");
    
    var response = await client.GetFromJsonAsync<JsonElement>(
        $"{project}/_apis/git/pullrequests?searchCriteria.creatorId={email}&api-version=7.0");
    
    return Results.Ok(response);
});
```

---

## Step 3: Create the Analysis Prompt

Save this prompt in the Prompts Library:

**Name:** Staff Productivity Analyzer

**Content:**
```
You are an expert in analyzing software development productivity metrics.

I will provide you with data about a developer including:
- Work items (bugs, tasks, user stories) they've worked on
- Commits they've made
- Pull requests they've created

Analyze this data and provide:

1. **Productivity Score** (1-10) based on:
   - Volume of work completed
   - Consistency of output
   - Quality indicators (bugs vs features)

2. **Strengths** - What they excel at

3. **Areas for Improvement** - Specific, actionable feedback

4. **Warning Signs** - Any concerning patterns like:
   - Long gaps between activity
   - High bug-to-feature ratio
   - Incomplete work items
   - Low code review participation

5. **Recommendations** - How to support this developer

Be constructive, specific, and data-driven. Avoid vague generalizations.
```

---

## Step 4: Create the Analysis Vue Component

Create `/opt/khaos/apps/web/src/views/TeamAnalysis.vue`:

```vue
<template>
  <div>
    <h1 class="text-h4 mb-4">Team Productivity Analysis</h1>
    
    <!-- Team Member Selection -->
    <v-card class="mb-4">
      <v-card-title>Select Team Member</v-card-title>
      <v-card-text>
        <v-row>
          <v-col cols="8">
            <v-text-field
              v-model="email"
              label="Team Member Email"
              placeholder="user@company.com"
            ></v-text-field>
          </v-col>
          <v-col cols="4">
            <v-btn color="primary" @click="analyze" :loading="loading" size="large">
              Analyze
            </v-btn>
          </v-col>
        </v-row>
      </v-card-text>
    </v-card>
    
    <!-- Raw Data -->
    <v-card v-if="data" class="mb-4">
      <v-card-title>Activity Summary (Last 30 Days)</v-card-title>
      <v-card-text>
        <v-row>
          <v-col cols="4">
            <v-card color="blue-lighten-4">
              <v-card-text class="text-center">
                <div class="text-h3">{{ data.workItems?.count || 0 }}</div>
                <div>Work Items</div>
              </v-card-text>
            </v-card>
          </v-col>
          <v-col cols="4">
            <v-card color="green-lighten-4">
              <v-card-text class="text-center">
                <div class="text-h3">{{ data.commits?.count || 0 }}</div>
                <div>Commits</div>
              </v-card-text>
            </v-card>
          </v-col>
          <v-col cols="4">
            <v-card color="purple-lighten-4">
              <v-card-text class="text-center">
                <div class="text-h3">{{ data.pullRequests?.count || 0 }}</div>
                <div>Pull Requests</div>
              </v-card-text>
            </v-card>
          </v-col>
        </v-row>
      </v-card-text>
    </v-card>
    
    <!-- AI Analysis -->
    <v-card v-if="analysis">
      <v-card-title>
        <v-icon color="primary" class="mr-2">mdi-robot</v-icon>
        AI Analysis
      </v-card-title>
      <v-card-text>
        <div class="analysis-content" v-html="formatAnalysis(analysis)"></div>
      </v-card-text>
    </v-card>
    
    <!-- Loading State -->
    <v-card v-if="loading">
      <v-card-text class="text-center pa-8">
        <v-progress-circular indeterminate size="48"></v-progress-circular>
        <div class="mt-4">{{ loadingMessage }}</div>
      </v-card-text>
    </v-card>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'

const email = ref('')
const loading = ref(false)
const loadingMessage = ref('')
const data = ref<any>(null)
const analysis = ref('')

const analyze = async () => {
  if (!email.value) return
  
  loading.value = true
  data.value = null
  analysis.value = ''
  
  try {
    // Step 1: Fetch data from Azure DevOps
    loadingMessage.value = 'Fetching work items...'
    const workItems = await fetch(`/api/devops/workitems/${encodeURIComponent(email.value)}`).then(r => r.json())
    
    loadingMessage.value = 'Fetching commits...'
    const commits = await fetch(`/api/devops/commits/${encodeURIComponent(email.value)}`).then(r => r.json())
    
    loadingMessage.value = 'Fetching pull requests...'
    const pullRequests = await fetch(`/api/devops/pullrequests/${encodeURIComponent(email.value)}`).then(r => r.json())
    
    data.value = { workItems, commits, pullRequests }
    
    // Step 2: Send to AI for analysis
    loadingMessage.value = 'AI is analyzing the data...'
    
    const prompt = `
Analyze this developer's productivity data:

## Work Items (${workItems.value?.length || 0} items)
${JSON.stringify(workItems.value?.slice(0, 10) || [], null, 2)}

## Commits (${commits.count || 0} commits)
${JSON.stringify(commits.commits?.slice(0, 10) || [], null, 2)}

## Pull Requests (${pullRequests.value?.length || 0} PRs)
${JSON.stringify(pullRequests.value?.slice(0, 10) || [], null, 2)}

Provide a comprehensive productivity analysis.
`
    
    const aiResponse = await fetch('/api/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: prompt, model: 'llama3.1:8b' })
    }).then(r => r.json())
    
    analysis.value = aiResponse.response
    
  } catch (error) {
    console.error('Analysis failed:', error)
    analysis.value = 'Error: Could not complete analysis. Check console for details.'
  }
  
  loading.value = false
}

const formatAnalysis = (text: string) => {
  // Convert markdown-style formatting to HTML
  return text
    .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
    .replace(/\n/g, '<br>')
    .replace(/## (.*?)(<br>|$)/g, '<h3>$1</h3>')
}
</script>

<style scoped>
.analysis-content {
  line-height: 1.8;
}
.analysis-content h3 {
  margin-top: 16px;
  color: #1976d2;
}
</style>
```

---

## Step 5: Register the Route

Update `/opt/khaos/apps/web/src/main.ts`:

```typescript
import TeamAnalysis from './views/TeamAnalysis.vue'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', component: Home },
    { path: '/chat', component: Chat },
    { path: '/redis', component: Redis },
    { path: '/team', component: TeamAnalysis }  // Add this
  ]
})
```

Update `/opt/khaos/apps/web/src/App.vue` navigation:

```vue
<v-btn to="/team" variant="text">Team Analysis</v-btn>
```

---

## Step 6: Example Workflow

1. **Configure Azure DevOps credentials** in Redis Manager
2. Navigate to **Team Analysis** page
3. Enter team member's email address
4. Click **Analyze**
5. View:
   - Activity metrics (work items, commits, PRs)
   - AI-generated productivity analysis
   - Recommendations for improvement

---

## Advanced: Batch Team Analysis

Create an endpoint to analyze the whole team:

```csharp
app.MapPost("/api/devops/team-analysis", async (
    JsonElement body,
    IConnectionMultiplexer redis,
    IHttpClientFactory httpFactory) =>
{
    var emails = body.GetProperty("emails").EnumerateArray()
        .Select(e => e.GetString())
        .ToList();
    
    var results = new List<object>();
    
    foreach (var email in emails)
    {
        // Fetch data for each team member
        // ... (same logic as individual endpoints)
        
        results.Add(new { email, /* data */ });
    }
    
    return Results.Ok(results);
});
```

---

## Sample AI Questions

Use the Chat interface with these prompts:

1. **Identify struggling developers:**
   > "Given this team data, which developers show signs of struggling or burnout? What patterns indicate this?"

2. **Compare productivity:**
   > "Compare the productivity of Developer A vs Developer B based on their metrics. Who is more effective and why?"

3. **Predict issues:**
   > "Based on the declining commit frequency for this developer, what potential issues should we watch for?"

4. **Team health:**
   > "Analyze the overall team velocity trend. Is the team improving, declining, or stable?"

---

## Privacy & Ethics Considerations

⚠️ **Important Notes:**

1. **Transparency** - Inform team members their data is being analyzed
2. **Context** - Numbers don't tell the whole story (meetings, mentoring, design work)
3. **Fairness** - Compare similar roles only
4. **Purpose** - Use for support, not punishment
5. **Privacy** - Store only necessary data, implement access controls

---

*This use case demonstrates how Khaos Server can integrate with external APIs and use AI for meaningful analysis.*
