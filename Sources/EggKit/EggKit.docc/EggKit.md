# EggKit

Build agent-ready scaffolding workflows with egg.

## Overview

egg is a template scaffolding system for humans and AI agents. Templates define
typed macros in `config.yml`, use `___MACRO_NAME___` placeholders in files and
directories, and hatch into reviewed project changes.

The command line interface is intentionally split into two modes:

- Human workflows use `egg hatch` or `egg hatch direct`.
- Agent workflows use `egg hatch preview`, `apply`, `rollback`, and `discard`
  with JSON output.

The repository also ships Agent Skills, Claude Code and Codex plugin manifests,
and a built-in MCP server so assistants can discover template requirements
before changing a project.

## Topics

### Getting Started

- <doc:GettingStarted>
- <doc:AgentSkillsAndPlugins>
- <doc:TemplateConfig>
- <doc:TransactionFlow>
- <doc:ManagingTemplates>

### Reference

- <doc:BuiltInMacros>

