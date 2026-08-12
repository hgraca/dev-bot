---
layout: home
title: DevBot
---

<section class="hero">
  <div class="container">
    <div class="hero-badge">Open Source &middot; Pair Programming Agent &middot; Remembers your project &middot; Bring your own modules</div>
    <h1>Your coding agent, supercharged</h1>
    <p class="hero-subtitle">
      DevBot is a meta-harness that provides a <strong>pair programming partner</strong> that never forgets — persistent memory,
      deep codebase understanding, and instant context across sessions.<br>
      Install once, use in every project.<br>
      Use with OpenCode or ClaudeCode.<br>
    </p>
    <div class="hero-install">
      <span class="prompt">$</span> git clone git@github.com:hgraca/dev-bot.git &amp;&amp; cd dev-bot<br>
      <span class="prompt">$</span> make install<br>
      <span class="optional"><span class="prompt">$</span> optional: adjust `.devbot.global.jsonc`</span><br>
      <span class="prompt">$</span> cd path/to/your-project &amp;&amp; devbot init<br>
      <span class="optional"><span class="prompt">$</span> optional: adjust `.devbot.project.jsonc` and do `devbot reinit`</span><br>
      <span class="prompt">$</span> devbot
    </div>
    <div class="hero-actions">
      <a href="{{ '/agents' | relative_url }}" class="btn btn-primary">Read the docs</a>
      <a href="https://github.com/hgraca/dev-bot" class="btn btn-secondary" target="_blank" rel="noopener">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/></svg>
        View on GitHub
      </a>
    </div>
  </div>
</section>

<section class="section">
  <div class="container">
    <div class="section-header">
      <h2>Two ways to work</h2>
    </div>
    <div class="feature-grid">
      <div class="feature-card" style="border-color: var(--accent); box-shadow: 0 0 0 1px rgba(108,123,255,.25);">
        <div class="feature-icon">&#x1f91d;</div>
        <h3>DevBot Agent <span class="badge-recommended">Recommended</span></h3>
        <p><strong>Pair programming partner.</strong> Sits alongside you, thinks together, writes together incrementally. Primes context at session start, recalls past decisions, loads the right skills for whatever you're building. <em>Never autonomous — you're always in control.</em></p>
      </div>
      <div class="feature-card">
        <div class="feature-icon">&#x1f465;</div>
        <h3>TeamLead Orchestrator <span class="badge-power">Power User</span></h3>
        <p><strong>Full delegation.</strong> Classifies work, routes to specialized subagents (Architect, Developer, Tester, Reviewer, Critic, PO, Scout, Security). Structured plan&rarr;implement&rarr;review cycles with verified deliverables at every gate.</p>
      </div>
  </div>
</section>

<section class="section section-alt">
  <div class="container">
    <div class="section-header">
      <h2>What powers both agents</h2>
      <p>Whether you pair-program or delegate, the same infrastructure works under the hood.</p>
    </div>
    <div class="feature-grid">
      <div class="feature-card">
        <div class="feature-icon">&#x1f9e0;</div>
        <h3>Persistent Memory</h3>
        <p>Decisions, bugs, and patterns survive across sessions and projects. Learnings auto-capture after every commit.</p>
      </div>
      <div class="feature-card">
        <div class="feature-icon">&#x1f4d6;</div>
        <h3>Curated Knowledge Vault</h3>
        <p>Human-readable notes survive model resets &mdash; architecture decisions, product decisions, gotchas, and patterns.</p>
      </div>
      <div class="feature-card">
        <div class="feature-icon">&#x1f504;</div>
        <h3>Autonomously Learns &amp; Recalls</h3>
        <p>Automatically captures decisions, gotchas, and patterns after each session. Recalls relevant learnings when you encounter similar situations.</p>
      </div>
      <div class="feature-card">
        <div class="feature-icon">&#x1f50d;</div>
        <h3>Codebase Understanding</h3>
        <p>Semantic code search and a structural knowledge graph find code by meaning, trace dependencies, and map call graphs.</p>
      </div>
      <div class="feature-card">
        <div class="feature-icon">&#x1f4e6;</div>
        <h3>Extensible Modules</h3>
        <p>Adapt to other harnesses, add third-party agents, commands, skills, and tools from any git repo. One command wires them in.</p>
      </div>
      <div class="feature-card">
        <div class="feature-icon">&#x1f6e1;&#xfe0f;</div>
        <h3>Command Guards</h3>
        <p>Regex-based rules block dangerous bash commands before they execute. Configurable per project.</p>
      </div>
    </div>
  </div>
</section>

<section class="section">
  <div class="container">
    <div class="section-header">
      <h2>What you get</h2>
    </div>
    <ul class="highlight-list">
      <li>
        <span class="check">&#x2713;</span>
        <span><strong>Pair programming agent</strong> &mdash; the DevBot agent is your default experience. Thinks with you, never autonomously. Remembers past sessions, recalls gotchas, loads the right skills.</span>
      </li>
      <li>
        <span class="check">&#x2713;</span>
        <span><strong>Full delegation when you need it</strong> &mdash; switch to TeamLead for structured multi-agent workflows: plan &rarr; implement &rarr; review with 8 specialized subagents.</span>
      </li>
      <li>
        <span class="check">&#x2713;</span>
        <span><strong>Works with OpenCode and Claude Code</strong> &mdash; dual harness support with consistent agent behavior across platforms. Bring your own harness if not yet supported.</span>
      </li>
      <li>
        <span class="check">&#x2713;</span>
        <span><strong>Automatic knowledge capture</strong> &mdash; learnings promoted to memory after each commit. No manual intervention.</span>
      </li>
      <li>
        <span class="check">&#x2713;</span>
        <span><strong>Rich MCP integrations</strong> &mdash; browser DevTools, Playwright, semantic code search, library docs, web search, and more.</span>
      </li>
      <li>
        <span class="check">&#x2713;</span>
        <span><strong>Extensible with modules</strong> &mdash; add third-party agents, commands, skills, and tools from any git repo. One command wires them into every project.</span>
      </li>
    </ul>
  </div>
</section>

<section class="section section-alt">
  <div class="container">
    <div class="section-header">
      <h2>Tools under the hood</h2>
      <p>Every tool runs locally. DevBot installs, configures, and manages them all.</p>
    </div>
    <div class="feature-grid">
      <div class="feature-card">
        <h3><a href="{{ '/tools/graphify' | relative_url }}">Graphify</a></h3>
        <p>Structural knowledge graph auto-built from your codebase. Query file relationships, trace call graphs, detect community boundaries.</p>
      </div>
      <div class="feature-card">
        <h3><a href="{{ '/tools/codebase-index' | relative_url }}">Codebase Index</a></h3>
        <p>Semantic code search &mdash; find functions, classes, and patterns by describing what they do. Embeddings via Ollama.</p>
      </div>
      <div class="feature-card">
        <h3><a href="{{ '/tools/qmd' | relative_url }}">QMD Knowledge Vault</a></h3>
        <p>Curated knowledge vault with semantic search. Goals, decisions, patterns, and gotchas in human-readable markdown notes.</p>
      </div>
      <div class="feature-card">
        <h3><a href="{{ '/tools/guards' | relative_url }}">Guards</a></h3>
        <p>Prevent dangerous commands from being executed by agents. Configure regex patterns to block risky operations before they run.</p>
      </div>
      <div class="feature-card">
        <h3><a href="{{ '/tools/plugins' | relative_url }}">Plugins</a></h3>
        <p>OpenCode lifecycle hooks that fire automatically &mdash; format on save, guard dangerous commands, auto-recover from errors.</p>
      </div>
      <div class="feature-card">
        <h3><a href="{{ '/tools/agent-communication' | relative_url }}">Agent Communication</a></h3>
        <p>Structured inter-agent protocol with terminal status markers. Orchestrator delegates to specialists with verified deliverables.</p>
      </div>
    </div>
    <div class="hero-actions" style="margin-top: 2.5rem;">
      <a href="{{ '/tools' | relative_url }}" class="btn btn-secondary">See all tools &rarr;</a>
      <a href="{{ '/modules-and-tools' | relative_url }}" class="btn btn-secondary">Modules &amp; Tools Map &rarr;</a>
    </div>
  </div>
</section>
