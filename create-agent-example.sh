#!/bin/bash

# Example Custom CLI Integration for VS Code Remote Agent Job Command
# This script demonstrates how to create a custom coding agent that integrates 
# with VS Code's workbench.action.chat.createRemoteAgentJob command

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="vscode-custom-agent-example"

echo "Setting up VS Code Custom Agent Integration Example..."

# 1. Create the extension structure
mkdir -p "${PROJECT_NAME}/src"
cd "${PROJECT_NAME}"

# 2. Create package.json with remote coding agent contribution
cat > package.json << 'EOF'
{
  "name": "vscode-custom-coding-agent",
  "displayName": "Custom Coding Agent",
  "description": "Example integration with workbench.action.chat.createRemoteAgentJob",
  "version": "0.0.1",
  "engines": {
    "vscode": "^1.85.0"
  },
  "categories": ["Other"],
  "activationEvents": [
    "onCommand:customAgent.execute"
  ],
  "main": "./out/extension.js",
  "contributes": {
    "commands": [
      {
        "command": "customAgent.execute",
        "title": "Execute Custom Agent"
      }
    ],
    "remoteCodingAgents": [
      {
        "id": "customCliAgent",
        "command": "customAgent.execute", 
        "displayName": "Custom CLI Agent",
        "description": "Delegates coding tasks to a custom CLI tool",
        "when": "config.customAgent.enabled"
      }
    ],
    "configuration": {
      "title": "Custom Agent",
      "properties": {
        "customAgent.enabled": {
          "type": "boolean",
          "default": true,
          "description": "Enable the custom coding agent"
        },
        "customAgent.cliPath": {
          "type": "string", 
          "default": "my-coding-cli",
          "description": "Path to the custom CLI executable"
        }
      }
    }
  },
  "scripts": {
    "vscode:prepublish": "npm run compile",
    "compile": "tsc -p ./",
    "watch": "tsc -watch -p ./"
  },
  "devDependencies": {
    "@types/vscode": "^1.85.0",
    "@types/node": "18.x",
    "typescript": "^5.0.0"
  }
}
EOF

# 3. Create TypeScript configuration
cat > tsconfig.json << 'EOF'
{
  "compilerOptions": {
    "module": "commonjs",
    "target": "es2020",
    "outDir": "out",
    "lib": [
      "es2020"
    ],
    "sourceMap": true,
    "rootDir": "src",
    "strict": true
  },
  "exclude": [
    "node_modules",
    ".vscode-test"
  ]
}
EOF

# 4. Create the main extension file
cat > src/extension.ts << 'EOF'
import * as vscode from 'vscode';
import { spawn } from 'child_process';
import * as path from 'path';
import * as os from 'os';
import * as fs from 'fs';

interface AgentRequest {
    userPrompt: string;
    summary: string;
    _version?: number;
}

interface AgentResponse {
    title: string;
    description?: string;
    url?: string;
}

export function activate(context: vscode.ExtensionContext) {
    console.log('Custom Coding Agent extension is now active!');
    
    // Register the command that will be called by workbench.action.chat.createRemoteAgentJob
    const disposable = vscode.commands.registerCommand('customAgent.execute', async (args: AgentRequest) => {
        return handleCodingRequest(args);
    });
    
    context.subscriptions.push(disposable);
    
    // Example: Also register a direct command for testing
    const testCommand = vscode.commands.registerCommand('customAgent.test', async () => {
        const testRequest: AgentRequest = {
            userPrompt: "Create a hello world function",
            summary: "User wants a simple hello world function",
            _version: 2
        };
        
        try {
            const result = await handleCodingRequest(testRequest);
            vscode.window.showInformationMessage(`Agent Result: ${JSON.stringify(result)}`);
        } catch (error) {
            vscode.window.showErrorMessage(`Agent Error: ${error}`);
        }
    });
    
    context.subscriptions.push(testCommand);
}

async function handleCodingRequest(args: AgentRequest): Promise<AgentResponse | string> {
    const config = vscode.workspace.getConfiguration('customAgent');
    const cliPath = config.get<string>('cliPath', 'my-coding-cli');
    
    console.log('Handling coding request:', args);
    
    try {
        // Method 1: Execute external CLI
        if (await isCliAvailable(cliPath)) {
            return await executeExternalCli(cliPath, args);
        }
        
        // Method 2: Built-in processing (fallback)
        return await processRequestLocally(args);
        
    } catch (error) {
        console.error('Error in coding agent:', error);
        throw error;
    }
}

async function isCliAvailable(cliPath: string): Promise<boolean> {
    return new Promise((resolve) => {
        const proc = spawn(cliPath, ['--version'], { stdio: 'pipe' });
        proc.on('error', () => resolve(false));
        proc.on('close', (code) => resolve(code === 0));
    });
}

async function executeExternalCli(cliPath: string, args: AgentRequest): Promise<AgentResponse> {
    return new Promise((resolve, reject) => {
        // Create temporary context file
        const tempFile = path.join(os.tmpdir(), `vscode-agent-${Date.now()}.json`);
        const contextData = {
            prompt: args.userPrompt,
            summary: args.summary,
            workspace: vscode.workspace.workspaceFolders?.[0]?.uri.fsPath,
            timestamp: new Date().toISOString()
        };
        
        fs.writeFileSync(tempFile, JSON.stringify(contextData, null, 2));
        
        // Execute CLI with context file
        const proc = spawn(cliPath, ['--context', tempFile], {
            stdio: ['pipe', 'pipe', 'pipe']
        });
        
        let stdout = '';
        let stderr = '';
        
        proc.stdout.on('data', (data) => {
            stdout += data.toString();
        });
        
        proc.stderr.on('data', (data) => {
            stderr += data.toString();
        });
        
        proc.on('close', (code) => {
            // Cleanup temp file
            try {
                fs.unlinkSync(tempFile);
            } catch (e) {
                console.warn('Failed to cleanup temp file:', e);
            }
            
            if (code === 0) {
                try {
                    // Parse CLI response
                    const response = JSON.parse(stdout);
                    resolve({
                        title: response.title || 'Task Completed',
                        description: response.description || stdout.trim(),
                        url: response.url
                    });
                } catch (parseError) {
                    // Fallback to text response
                    resolve({
                        title: 'Task Completed',
                        description: stdout.trim()
                    });
                }
            } else {
                reject(new Error(`CLI failed with code ${code}: ${stderr}`));
            }
        });
        
        proc.on('error', (error) => {
            reject(new Error(`Failed to execute CLI: ${error.message}`));
        });
    });
}

async function processRequestLocally(args: AgentRequest): Promise<AgentResponse> {
    // Fallback: Process request locally without external CLI
    // This is a simple example - replace with your actual logic
    
    const response: AgentResponse = {
        title: 'Request Processed Locally',
        description: `Processed: "${args.userPrompt}"\n\nSummary: ${args.summary}`
    };
    
    // Simulate some processing time
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // You could:
    // - Generate code using templates
    // - Make API calls to external services
    // - Process files in the workspace
    // - Create pull requests programmatically
    // - etc.
    
    return response;
}

export function deactivate() {}
EOF

# 5. Create an example CLI tool
cat > example-cli.js << 'EOF'
#!/usr/bin/env node

// Example CLI tool that can be called by the VS Code extension
// This simulates a coding agent that processes requests

const fs = require('fs');
const path = require('path');

function main() {
    const args = process.argv.slice(2);
    
    if (args.includes('--version')) {
        console.log('example-cli v1.0.0');
        process.exit(0);
    }
    
    if (args.includes('--help')) {
        console.log('Usage: example-cli --context <context-file>');
        process.exit(0);
    }
    
    const contextIndex = args.indexOf('--context');
    if (contextIndex === -1 || contextIndex === args.length - 1) {
        console.error('Missing --context argument');
        process.exit(1);
    }
    
    const contextFile = args[contextIndex + 1];
    
    try {
        const contextData = JSON.parse(fs.readFileSync(contextFile, 'utf8'));
        const result = processRequest(contextData);
        console.log(JSON.stringify(result, null, 2));
    } catch (error) {
        console.error('Error:', error.message);
        process.exit(1);
    }
}

function processRequest(context) {
    const { prompt, summary, workspace } = context;
    
    // Simulate processing the coding request
    // In a real implementation, this would:
    // - Analyze the prompt
    // - Generate or modify code
    // - Create commits/PRs
    // - Run tests
    // - etc.
    
    const result = {
        title: 'Code Generated Successfully',
        description: `Generated code based on: "${prompt}"`,
        url: null // Could be a PR URL, documentation link, etc.
    };
    
    // Example: Different responses based on the prompt
    if (prompt.toLowerCase().includes('hello world')) {
        result.description += '\n\nCreated a simple hello world function.';
    } else if (prompt.toLowerCase().includes('api')) {
        result.description += '\n\nGenerated REST API endpoints.';
    } else if (prompt.toLowerCase().includes('test')) {
        result.description += '\n\nCreated unit tests.';
    }
    
    if (workspace) {
        result.description += `\n\nWorkspace: ${workspace}`;
    }
    
    return result;
}

if (require.main === module) {
    main();
}

module.exports = { processRequest };
EOF

chmod +x example-cli.js

# 6. Create README with usage instructions
cat > README.md << 'EOF'
# VS Code Custom Coding Agent Example

This example demonstrates how to create a custom extension that integrates with VS Code's `workbench.action.chat.createRemoteAgentJob` command.

## Setup

1. Install dependencies:
   ```bash
   npm install
   ```

2. Compile the extension:
   ```bash
   npm run compile
   ```

3. Install the extension:
   - Open this folder in VS Code
   - Press F5 to run the Extension Development Host
   - Or package and install: `vsce package && code --install-extension *.vsix`

## Usage

### Via Chat Interface

1. Open a chat conversation in VS Code
2. Type a coding request (e.g., "create a hello world function")
3. Look for the "Delegate to Coding Agent" button in the chat interface
4. Select "Custom CLI Agent" from the dropdown
5. The extension will process your request

### Via Command Palette

1. Open Command Palette (Ctrl+Shift+P / Cmd+Shift+P)
2. Run "Custom Agent: Test" command
3. Check the notification for the result

## Configuration

The extension can be configured via VS Code settings:

```json
{
  "customAgent.enabled": true,
  "customAgent.cliPath": "./example-cli.js"
}
```

## External CLI Integration

The extension looks for an external CLI tool at the path specified in `customAgent.cliPath`. 

The CLI tool receives context via a JSON file:

```json
{
  "prompt": "user's coding request",
  "summary": "conversation summary", 
  "workspace": "/path/to/workspace",
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

Expected CLI response format:

```json
{
  "title": "Task completed",
  "description": "What was accomplished",
  "url": "https://optional-link-to-result"
}
```

## Architecture

```
VS Code Chat Interface
         ↓
workbench.action.chat.createRemoteAgentJob
         ↓ 
customAgent.execute command
         ↓
Extension handler
         ↓
External CLI (optional)
         ↓
Response back to chat
```

## Development

- Edit `src/extension.ts` to modify the extension logic
- Edit `example-cli.js` to modify the CLI tool behavior
- Run `npm run watch` for live compilation during development
- Use F5 in VS Code to test in Extension Development Host

## Real-World Usage

In a production environment, you would replace the example CLI with your actual coding agent:

- **AI Services**: Call GPT, Claude, or other AI APIs
- **Code Generation**: Use templates, ASTs, or code generation libraries  
- **Git Integration**: Create branches, commits, and pull requests
- **Testing**: Run test suites and report results
- **Deployment**: Trigger CI/CD pipelines
- **Documentation**: Generate docs, comments, README files

The key is implementing the command handler that VS Code's remote agent job system can call.
EOF

# 7. Create development scripts
cat > .vscode/launch.json << 'EOF'
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Run Extension",
            "type": "extensionHost",
            "request": "launch",
            "args": [
                "--extensionDevelopmentPath=${workspaceFolder}"
            ]
        }
    ]
}
EOF

mkdir -p .vscode

cat > .vscode/tasks.json << 'EOF'
{
    "version": "2.0.0",
    "tasks": [
        {
            "type": "npm",
            "script": "watch",
            "problemMatcher": "$tsc-watch",
            "isBackground": true,
            "presentation": {
                "reveal": "never"
            },
            "group": {
                "kind": "build",
                "isDefault": true
            }
        }
    ]
}
EOF

echo ""
echo "✅ Custom VS Code Agent Integration Example created successfully!"
echo ""
echo "📁 Project structure:"
echo "   ${PROJECT_NAME}/"
echo "   ├── package.json          # Extension manifest with remoteCodingAgents contribution"
echo "   ├── src/extension.ts      # Main extension code"
echo "   ├── example-cli.js        # Example external CLI tool"
echo "   ├── tsconfig.json         # TypeScript configuration"
echo "   └── README.md             # Usage instructions"
echo ""
echo "🚀 Next steps:"
echo "   cd ${PROJECT_NAME}"
echo "   npm install"
echo "   npm run compile"
echo "   code . # Open in VS Code and press F5 to test"
echo ""
echo "📖 See README.md for detailed usage instructions"

EOF

chmod +x /home/runner/work/vscode/vscode/create-agent-example.sh