---
layout: default
title: <Org> Documentation
description: Documentation sites across the <org> organisation, gathered in one place.
---

<section class="hero">
  <h1><Org> Documentation</h1>
  <p class="lead">Documentation sites across the <org> organisation, gathered in one place.</p>
</section>

{%- assign projects = site.data.projects | default: empty -%}
{%- if projects.size > 0 -%}
{%- assign groups = projects | group_by: "category" -%}
{%- for group in groups -%}
{%- if group.name and group.name != "" -%}
<h2 class="section-title">{{ group.name | escape }}</h2>
{%- endif -%}
<div class="project-grid">
{%- for project in group.items -%}
<a class="card" href="{{ project.docs_url | escape }}">
<span class="card-head">
<span class="card-name">{{ project.name | escape }}</span>
</span>
<span class="card-desc">{{ project.description | escape }}</span>
<span class="card-cta">View documentation &rarr;</span>
</a>
{%- endfor -%}
</div>
{%- endfor -%}
{%- else -%}
  <p class="empty">No documentation sites are published yet.</p>
{%- endif -%}
