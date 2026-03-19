#!/bin/bash
# Tasuki Engine — Dashboard Generator
# Generates a single static HTML file with interactive charts and knowledge graph.
# Uses Chart.js for charts, D3.js for force-directed graph.
# Usage: bash dashboard.sh [/path/to/project] [--watch]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
set +e
set +o pipefail

generate_dashboard() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"
  local output="$project_dir/.tasuki/dashboard.html"
  local project_name
  project_name=$(basename "$project_dir")

  log_info "Generating dashboard..."

  # Collect all data
  local graph_json
  graph_json=$(extract_graph_data "$project_dir")

  local history_json
  history_json=$(extract_history_data "$project_dir")

  local health_json
  health_json=$(extract_health_data "$project_dir")

  local agents_json
  agents_json=$(extract_agent_data "$project_dir")

  local progress_json
  progress_json=$(extract_progress_data "$project_dir")

  local activity_json
  activity_json=$(extract_activity_data "$project_dir")

  local rag_json
  rag_json=$(extract_rag_data "$project_dir")

  mkdir -p "$(dirname "$output")"

  # Generate HTML
  cat > "$output" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Tasuki Dashboard</title>
<link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 92 84'%3E%3Cline x1='18' y1='12' x2='52' y2='8' stroke='%23D8D4CC' stroke-width='1.2' opacity='0.55'/%3E%3Cline x1='52' y1='8' x2='72' y2='28' stroke='%23F5E642' stroke-width='1.2' opacity='0.5'/%3E%3Cline x1='72' y1='28' x2='62' y2='48' stroke='%234A9EFF' stroke-width='1.2' opacity='0.52'/%3E%3Cline x1='62' y1='48' x2='38' y2='58' stroke='%2300D4FF' stroke-width='1.2' opacity='0.52'/%3E%3Cline x1='38' y1='58' x2='28' y2='72' stroke='%23FF7B6B' stroke-width='1.2' opacity='0.46'/%3E%3Cline x1='28' y1='72' x2='58' y2='72' stroke='%23FF4444' stroke-width='1.2' opacity='0.56'/%3E%3Cline x1='58' y1='72' x2='76' y2='60' stroke='%234ADE80' stroke-width='1.2' opacity='0.5'/%3E%3Ccircle cx='18' cy='12' r='4.5' fill='%23D8D4CC'/%3E%3Ccircle cx='52' cy='8' r='4' fill='%23F5E642'/%3E%3Ccircle cx='72' cy='28' r='3.5' fill='%234A9EFF'/%3E%3Ccircle cx='62' cy='48' r='5' fill='%2300D4FF'/%3E%3Ccircle cx='38' cy='58' r='4' fill='%23FF7B6B'/%3E%3Ccircle cx='28' cy='72' r='4.5' fill='%23FF4444'/%3E%3Ccircle cx='58' cy='72' r='4.5' fill='%234ADE80'/%3E%3Ccircle cx='76' cy='60' r='3.5' fill='%23A0A8B0'/%3E%3C/svg%3E" />
<script src="https://cdn.jsdelivr.net/npm/chart.js@4"></script>
<script src="https://d3js.org/d3.v7.min.js"></script>
<style>
@import url('https://fonts.googleapis.com/css2?family=Instrument+Sans:wght@400;500;600;700&family=DM+Mono:wght@400;500&display=swap');
* { margin: 0; padding: 0; box-sizing: border-box; }
:root {
  --bg: #0d1117; --surface: #161b22; --surface2: #1c2129; --border: #30363d;
  --text: #e6edf3; --text-dim: #8b949e; --accent: #58a6ff;
  --green: #3fb950; --yellow: #d29922; --red: #f85149;
  --purple: #bc8cff; --cyan: #39d2c0; --orange: #f0883e;
  --planner: #D8D4CC; --qa: #F5E642; --dbarch: #4A9EFF;
  --backend: #00D4FF; --frontend: #FF7B6B; --debugger: #FF8C2B;
  --security: #FF4444; --reviewer: #4ADE80; --devops: #A0A8B0;
}
body { font-family: 'Instrument Sans', -apple-system, BlinkMacSystemFont, sans-serif; background: var(--bg); color: var(--text); }
.mono { font-family: 'DM Mono', monospace; }

.header {
  padding: 14px 32px; border-bottom: 1px solid var(--border);
  display: flex; align-items: center; gap: 14px; background: #0a0e13;
}
.header-logo { display: flex; align-items: center; gap: 10px; text-decoration: none; }
.header-wordmark { font-family: 'Instrument Sans', sans-serif; font-weight: 700; font-size: 18px; letter-spacing: -0.04em; color: var(--text); }
.header-project { color: var(--text-dim); font-size: 13px; }
.header-project::before { content: '/ '; opacity: 0.4; }
.mode-pill { padding: 3px 10px; border-radius: 12px; font-size: 11px; font-weight: 600; font-family: 'DM Mono', monospace; }
.mode-pill.fast { background: rgba(63,185,80,0.15); color: var(--green); }
.mode-pill.standard { background: rgba(210,153,34,0.15); color: var(--yellow); }
.mode-pill.serious { background: rgba(248,81,73,0.15); color: var(--red); }
.refresh-btn { margin-left: auto; padding: 6px 14px; background: var(--surface); border: 1px solid var(--border); color: var(--text-dim); border-radius: 6px; cursor: pointer; font-size: 12px; display: flex; align-items: center; gap: 6px; }
.refresh-btn:hover { border-color: var(--accent); color: var(--accent); }
.gen-time { font-size: 11px; color: var(--text-dim); }

.grid { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; padding: 24px; max-width: 1400px; margin: 0 auto; }
.card { background: var(--surface); border: 1px solid var(--border); border-radius: 12px; padding: 18px; position: relative; overflow: hidden; }
.card::before { content: ''; position: absolute; top: 0; left: 0; right: 0; height: 1px; background: linear-gradient(90deg, transparent, var(--border), transparent); }
.card h2 { font-size: 13px; color: var(--text-dim); text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 16px; }
.card.full { grid-column: 1 / -1; }

/* Pipeline progress with agent characters */
.pipeline-agents-row { display: flex; align-items: flex-end; justify-content: space-between; gap: 4px; margin: 20px 0 8px; padding: 0 4px; }
.pipeline-agent-slot { display: flex; flex-direction: column; align-items: center; gap: 4px; flex: 1; position: relative; }
.pipeline-agent-char { width: 48px; height: 60px; display: flex; align-items: flex-end; justify-content: center; transition: opacity 0.3s, filter 0.3s; }
.pipeline-agent-char.done { opacity: 1; filter: none; }
.pipeline-agent-char.running { opacity: 1; filter: drop-shadow(0 0 8px currentColor) drop-shadow(0 0 18px currentColor); }
.pipeline-agent-char.pending { opacity: 0.12; filter: grayscale(1); }
.pipeline-agent-name { font-size: 9px; color: var(--text-dim); text-align: center; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 52px; }
.pipeline-agent-slot.done .pipeline-agent-name { color: var(--green); font-weight: 600; }
.pipeline-agent-slot.running .pipeline-agent-name { font-weight: 600; }
.pipeline-agent-slot .check { position: absolute; top: 0; right: 2px; width: 14px; height: 14px; border-radius: 50%; background: var(--green); display: flex; align-items: center; justify-content: center; font-size: 8px; color: #000; opacity: 0; }
.pipeline-agent-slot.done .check { opacity: 1; }
.glow-ring { position:absolute; width:56px; height:56px; border-radius:50%; top:2px; left:50%; transform:translateX(-50%); z-index:0; pointer-events:none; }
@keyframes glow-ring-pulse { 0%,100%{ opacity:0.3; transform:translateX(-50%) scale(1); } 50%{ opacity:0.7; transform:translateX(-50%) scale(1.2); } }
.pipeline-track { height: 4px; background: var(--border); border-radius: 2px; margin: 0 4px 16px; position: relative; overflow: hidden; }
.pipeline-track-fill { height: 100%; border-radius: 2px; background: var(--green); transition: width 0.5s ease; }
.pipeline-meta { display: flex; justify-content: space-between; align-items: center; font-size: 12px; color: var(--text-dim); margin-bottom: 14px; }
.pipeline-task-name { font-size: 14px; font-weight: 600; color: var(--text); margin-bottom: 6px; }
.pipeline-empty { color: var(--text-dim); text-align: center; padding: 28px 0; font-size: 13px; }
.stage-list { margin-top: 12px; }
.stage-row { display: flex; justify-content: space-between; align-items: center; padding: 5px 0; border-bottom: 1px solid var(--border); font-size: 12px; }
.stage-row:last-child { border-bottom: none; }
.stage-icon-done { color: var(--green); }
.stage-icon-running { color: var(--yellow); }
.stage-icon-pending { color: var(--border); }
.stage-time { color: var(--text-dim); font-size: 11px; }

/* Speech bubbles */
.speech-bubble { position: absolute; top: -28px; left: 50%; transform: translateX(-50%); background: var(--surface2, #1c2129); border: 1px solid var(--border); border-radius: 8px; padding: 3px 8px; font-size: 8px; color: var(--text-dim); white-space: nowrap; max-width: 120px; overflow: hidden; text-overflow: ellipsis; opacity: 0; transition: opacity 0.3s; pointer-events: none; z-index: 10; }
.speech-bubble::after { content: ''; position: absolute; bottom: -5px; left: 50%; transform: translateX(-50%); width: 0; height: 0; border-left: 4px solid transparent; border-right: 4px solid transparent; border-top: 5px solid var(--border); }
.pipeline-agent-slot.running .speech-bubble { opacity: 1; }
.pipeline-agent-slot.done .speech-bubble { opacity: 0.6; }

/* Activity animations */
@keyframes agent-typing { 0%,100%{ transform: translateY(0); } 15%{ transform: translateY(-2px); } 30%{ transform: translateY(0); } 45%{ transform: translateY(-2px); } 60%{ transform: translateY(0); } }
@keyframes agent-reading { 0%,100%{ transform: rotate(0deg); } 25%{ transform: rotate(-3deg); } 75%{ transform: rotate(3deg); } }
@keyframes agent-thinking { 0%,100%{ transform: scale(1); } 50%{ transform: scale(1.05); } }
@keyframes agent-reviewing { 0%{ transform: translateX(0); } 25%{ transform: translateX(2px); } 50%{ transform: translateX(0); } 75%{ transform: translateX(-2px); } }
@keyframes agent-shielding { 0%,100%{ filter: drop-shadow(0 0 8px currentColor); } 50%{ filter: drop-shadow(0 0 16px currentColor) drop-shadow(0 0 24px currentColor); } }
.pipeline-agent-slot.running[data-activity="typing"] .pipeline-agent-char svg { animation: agent-typing 0.6s ease-in-out infinite; }
.pipeline-agent-slot.running[data-activity="reading"] .pipeline-agent-char svg { animation: agent-reading 2s ease-in-out infinite; }
.pipeline-agent-slot.running[data-activity="thinking"] .pipeline-agent-char svg { animation: agent-thinking 1.5s ease-in-out infinite; }
.pipeline-agent-slot.running[data-activity="reviewing"] .pipeline-agent-char svg { animation: agent-reviewing 0.8s ease-in-out infinite; }
.pipeline-agent-slot.running[data-activity="shielding"] .pipeline-agent-char svg { animation: agent-shielding 1.2s ease-in-out infinite; }

.graph-container { height: 450px; position: relative; }
.chart-container { height: 250px; position: relative; }
.score-big { font-size: 64px; font-weight: 700; text-align: center; line-height: 1; }
.score-label { text-align: center; color: var(--text-dim); margin-top: 8px; }
.score-bar { display: flex; gap: 2px; justify-content: center; margin: 16px 0; }
.score-bar .block { width: 20px; height: 20px; border-radius: 4px; }
.score-bar .active { background: var(--green); }
.score-bar .warn { background: var(--yellow); }
.score-bar .empty { background: var(--border); }
.breakdown { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-top: 16px; }
.breakdown-item { display: flex; justify-content: space-between; padding: 6px 0; border-bottom: 1px solid var(--border); font-size: 13px; }
.breakdown-item .label { color: var(--text-dim); }
.stat-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; }
.stat { text-align: center; }
.stat .value { font-size: 32px; font-weight: 700; color: var(--accent); }
.stat .label { font-size: 12px; color: var(--text-dim); margin-top: 4px; }
.timeline { list-style: none; }
.timeline li { padding: 8px 0; border-bottom: 1px solid var(--border); display: flex; gap: 12px; font-size: 13px; }
.timeline .time { color: var(--text-dim); min-width: 140px; }
.timeline .agents { color: var(--cyan); font-size: 11px; margin-top: 2px; }
.legend { display: flex; gap: 12px; flex-wrap: wrap; margin-bottom: 12px; }
.legend-item { display: flex; align-items: center; gap: 6px; font-size: 12px; color: var(--text-dim); cursor: pointer; padding: 4px 10px; border-radius: 6px; border: 1px solid transparent; user-select: none; transition: all 0.15s; }
.legend-item:hover { border-color: var(--border); }
.legend-item.active { border-color: var(--accent); color: var(--text); }
.legend-item.hidden { opacity: 0.3; }
.legend-dot { width: 10px; height: 10px; border-radius: 50%; }
svg text { fill: var(--text); font-size: 11px; }
.mode-badge { padding: 2px 8px; border-radius: 10px; font-size: 11px; font-weight: 600; }
.mode-fast { background: rgba(63,185,80,0.15); color: var(--green); }
.mode-standard { background: rgba(210,153,34,0.15); color: var(--yellow); }
.mode-serious { background: rgba(248,81,73,0.15); color: var(--red); }
#cost-table tbody tr { border-bottom: 1px solid var(--border); transition: background 0.1s; }
#cost-table tbody tr:hover { background: rgba(88,166,255,0.05); }
.token-bar { display: inline-block; height: 6px; border-radius: 3px; background: var(--accent); margin-right: 8px; vertical-align: middle; }
.live-dot { width: 8px; height: 8px; border-radius: 50%; background: var(--green); display: inline-block; animation: live-pulse 2s ease-in-out infinite; }
.live-dot.disconnected { background: var(--red); animation: none; }
@keyframes live-pulse { 0%,100%{ opacity:1; } 50%{ opacity:0.3; } }
::-webkit-scrollbar { width: 6px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: var(--border); border-radius: 3px; }
::-webkit-scrollbar-thumb:hover { background: var(--text-dim); }
</style>
</head>
<body>

<div class="header">
  <a class="header-logo" href="#">
    <svg width="28" height="28" viewBox="0 0 92 84" fill="none">
      <line x1="18" y1="12" x2="52" y2="8" stroke="#D8D4CC" stroke-width="1.2" opacity="0.55"/>
      <line x1="18" y1="12" x2="14" y2="44" stroke="#D8D4CC" stroke-width="1.2" opacity="0.25"/>
      <line x1="52" y1="8" x2="72" y2="28" stroke="#F5E642" stroke-width="1.2" opacity="0.5"/>
      <line x1="52" y1="8" x2="62" y2="48" stroke="#F5E642" stroke-width="1.2" opacity="0.42"/>
      <line x1="72" y1="28" x2="62" y2="48" stroke="#4A9EFF" stroke-width="1.2" opacity="0.52"/>
      <line x1="62" y1="48" x2="38" y2="58" stroke="#00D4FF" stroke-width="1.2" opacity="0.52"/>
      <line x1="62" y1="48" x2="14" y2="44" stroke="#00D4FF" stroke-width="1.2" opacity="0.22"/>
      <line x1="38" y1="58" x2="14" y2="44" stroke="#FF7B6B" stroke-width="1.2" opacity="0.32"/>
      <line x1="38" y1="58" x2="28" y2="72" stroke="#FF7B6B" stroke-width="1.2" opacity="0.46"/>
      <line x1="28" y1="72" x2="58" y2="72" stroke="#FF4444" stroke-width="1.2" opacity="0.56"/>
      <line x1="58" y1="72" x2="76" y2="60" stroke="#4ADE80" stroke-width="1.2" opacity="0.5"/>
      <line x1="62" y1="48" x2="76" y2="60" stroke="#00D4FF" stroke-width="1.2" opacity="0.2"/>
      <circle cx="18" cy="12" r="4.5" fill="#D8D4CC"/>
      <circle cx="52" cy="8" r="4" fill="#F5E642"/>
      <circle cx="72" cy="28" r="3.5" fill="#4A9EFF"/>
      <circle cx="62" cy="48" r="5" fill="#00D4FF"/>
      <circle cx="38" cy="58" r="4" fill="#FF7B6B"/>
      <circle cx="14" cy="44" r="3" fill="#FF8C2B"/>
      <circle cx="28" cy="72" r="4.5" fill="#FF4444"/>
      <circle cx="58" cy="72" r="4.5" fill="#4ADE80"/>
      <circle cx="76" cy="60" r="3.5" fill="#A0A8B0"/>
    </svg>
    <span class="header-wordmark">tasuki</span>
  </a>
  <span class="header-project" id="project-name"></span>
  <button class="refresh-btn" onclick="fetch('/refresh').then(()=>location.reload())">↻ Refresh</button>
  <span class="live-dot" id="live-dot" title="Live — watching for changes"></span>
  <span class="gen-time" id="generated-time"></span>
</div>

<div class="grid">
  <!-- Knowledge Graph -->
  <div class="card full">
    <h2>Knowledge Graph</h2>
    <div class="legend" id="graph-legend"></div>
    <div class="graph-container" id="graph"></div>
  </div>

  <!-- Health Score -->
  <div class="card">
    <h2>Health Score</h2>
    <div class="score-big" id="health-score"></div>
    <div class="score-label">/ 100</div>
    <div class="score-bar" id="health-bar"></div>
    <div class="breakdown" id="health-breakdown"></div>
  </div>

  <!-- Stats Overview -->
  <div class="card">
    <h2>Overview</h2>
    <div class="stat-grid" id="stats"></div>
  </div>

  <!-- Pipeline Progress with Agent Characters -->
  <div class="card full">
    <h2>Pipeline Status</h2>
    <div id="pipeline-progress"></div>
  </div>

  <!-- Agent Usage -->
  <div class="card">
    <h2>Agent Usage</h2>
    <div class="chart-container"><canvas id="agent-chart"></canvas></div>
  </div>

  <!-- Mode Distribution -->
  <div class="card">
    <h2>Mode Distribution</h2>
    <div class="chart-container"><canvas id="mode-chart"></canvas></div>
  </div>

  <!-- Cost per Task -->
  <div class="card full">
    <h2>Cost per Task</h2>
    <div style="overflow-x:auto">
      <table id="cost-table" style="width:100%;border-collapse:collapse;font-size:13px;">
        <thead>
          <tr style="border-bottom:2px solid var(--border);text-align:left;">
            <th style="padding:10px;color:var(--text-dim)">Task</th>
            <th style="padding:10px;color:var(--text-dim)">Mode</th>
            <th style="padding:10px;color:var(--text-dim)">Score</th>
            <th style="padding:10px;color:var(--text-dim)">Pipeline</th>
            <th style="padding:10px;color:var(--text-dim);text-align:right">Tokens</th>
            <th style="padding:10px;color:var(--text-dim);text-align:right">USD</th>
          </tr>
        </thead>
        <tbody id="cost-body"></tbody>
        <tfoot id="cost-footer"></tfoot>
      </table>
    </div>
  </div>

  <!-- Cost Chart + Complexity -->
  <div class="card">
    <h2>Cost Over Time</h2>
    <div class="chart-container"><canvas id="cost-chart"></canvas></div>
  </div>

  <div class="card">
    <h2>Complexity Distribution</h2>
    <div class="chart-container"><canvas id="complexity-chart"></canvas></div>
  </div>

  <!-- Timeline -->
  <div class="card full">
    <h2>Recent Activity</h2>
    <ul class="timeline" id="timeline"></ul>
  </div>

  <!-- RAG Deep Memory Explorer -->
  <div class="card full">
    <h2>Deep Memory (RAG)</h2>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-bottom:16px">
      <div>
        <div id="rag-stats" style="display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin-bottom:12px"></div>
        <div id="rag-treemap" style="height:220px;position:relative;border-radius:8px;overflow:hidden"></div>
      </div>
      <div>
        <div style="margin-bottom:8px;display:flex;gap:8px;align-items:center">
          <input type="text" id="rag-search" placeholder="Search memories..." style="flex:1;padding:7px 12px;background:var(--bg);border:1px solid var(--border);border-radius:6px;color:var(--text);font-size:12px;outline:none" />
          <select id="rag-filter" style="padding:7px;background:var(--bg);border:1px solid var(--border);border-radius:6px;color:var(--text);font-size:11px;outline:none">
            <option value="all">All types</option>
          </select>
        </div>
        <div id="rag-entries" style="max-height:250px;overflow-y:auto;font-size:12px"></div>
      </div>
    </div>
    <div id="rag-detail" style="display:none;margin-top:12px;padding:16px;background:var(--bg);border:1px solid var(--border);border-radius:8px;max-height:300px;overflow-y:auto">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px">
        <span id="rag-detail-title" style="font-weight:600;font-size:14px"></span>
        <button onclick="document.getElementById('rag-detail').style.display='none'" style="background:none;border:none;color:var(--text-dim);cursor:pointer;font-size:16px">✕</button>
      </div>
      <div id="rag-detail-meta" style="font-size:11px;color:var(--text-dim);margin-bottom:8px"></div>
      <pre id="rag-detail-content" style="font-size:12px;color:var(--text);white-space:pre-wrap;word-break:break-word;font-family:'DM Mono',monospace;line-height:1.5"></pre>
    </div>
  </div>

  <!-- What Tasuki Did For You -->
  <div class="card full">
    <h2>What Tasuki Did For You</h2>
    <div id="activity-impact" style="display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin-bottom:16px"></div>
    <div id="activity-log" style="max-height:200px;overflow-y:auto"></div>
  </div>
</div>

<script>
HTMLEOF

  # Embed data
  cat >> "$output" << DATAEOF
const PROJECT = "$project_name";
const GENERATED = "$(date '+%Y-%m-%d %H:%M')";
const GRAPH = $graph_json;
const HISTORY = $history_json;
const HEALTH = $health_json;
const AGENTS = $agents_json;
const PROGRESS = $progress_json;
const ACTIVITY = $activity_json;
const RAG = $rag_json;
DATAEOF

  # Embed the rendering logic
  cat >> "$output" << 'JSEOF'

document.getElementById('project-name').textContent = PROJECT;
const modePill = document.createElement('span');
modePill.className = 'mode-pill ' + (PROGRESS.mode || 'standard');
modePill.textContent = PROGRESS.mode || 'standard';
document.querySelector('.header').insertBefore(modePill, document.querySelector('.refresh-btn'));
document.getElementById('generated-time').textContent = 'Generated: ' + GENERATED;

// ── AGENT CHARACTERS (inline SVG per agent) ──────────────────────────────────
const AGENT_SVG = {
  planner: `<svg width="48" height="56" viewBox="0 0 90 100" fill="none"><g><animateTransform attributeName="transform" type="translate" values="0,0;0,-3;0,0" dur="0.7s" repeatCount="indefinite"/><ellipse cx="40" cy="97" rx="20" ry="3.5" fill="#D8D4CC" opacity="0.1"/><rect x="18" y="40" width="44" height="34" rx="10" fill="#B8B4AC"/><rect x="14" y="8" width="52" height="46" rx="22" fill="#D8D4CC"/><rect x="22" y="24" width="9" height="11" rx="4.5" fill="#1A1A1A"/><rect x="49" y="24" width="9" height="11" rx="4.5" fill="#1A1A1A"/><rect x="25" y="22" width="4" height="5" rx="2" fill="white"/><rect x="52" y="22" width="4" height="5" rx="2" fill="white"/><rect x="21" y="20" width="11" height="3" rx="1.5" fill="#9A9890"/><rect x="48" y="18" width="11" height="3" rx="1.5" fill="#9A9890" transform="rotate(-7 53 19)"/><path d="M32 38 Q40 43 48 38" stroke="#9A9890" stroke-width="2" stroke-linecap="round" fill="none"/><ellipse cx="21" cy="36" rx="5" ry="3" fill="#C8C4BC" opacity="0.5"/><ellipse cx="59" cy="36" rx="5" ry="3" fill="#C8C4BC" opacity="0.5"/><rect x="4" y="44" width="16" height="10" rx="5" fill="#B8B4AC"/><g><animateTransform attributeName="transform" type="rotate" values="0 60 47;-20 60 47;0 60 47;8 60 47;0 60 47" dur="0.8s" repeatCount="indefinite"/><rect x="60" y="42" width="16" height="10" rx="5" fill="#B8B4AC"/><rect x="62" y="28" width="15" height="20" rx="3" fill="#222" stroke="#D8D4CC" stroke-width="0.8" opacity="0.9"/><rect x="67" y="25" width="7" height="5" rx="2" fill="#D8D4CC" opacity="0.7"/><rect x="64" y="33" width="11" height="1.5" rx="1" fill="#D8D4CC" opacity="0.4"/><rect x="64" y="37" width="8" height="1.5" rx="1" fill="#D8D4CC" opacity="0.3"/><rect x="64" y="41" width="9" height="1.5" rx="1" fill="#D8D4CC" opacity="0.3"/></g><rect x="24" y="70" width="12" height="22" rx="6" fill="#9A9890"/><rect x="44" y="70" width="12" height="22" rx="6" fill="#9A9890"/><rect x="20" y="86" width="16" height="8" rx="4" fill="#7A7870"/><rect x="44" y="86" width="16" height="8" rx="4" fill="#7A7870"/></g></svg>`,
  qa: `<svg width="48" height="56" viewBox="0 0 90 100" fill="none"><g><animateTransform attributeName="transform" type="translate" values="0,0;0,-3;0,0" dur="0.7s" repeatCount="indefinite"/><ellipse cx="40" cy="97" rx="20" ry="3.5" fill="#F5E642" opacity="0.1"/><rect x="18" y="40" width="44" height="34" rx="10" fill="#C8BC00"/><rect x="14" y="8" width="52" height="46" rx="22" fill="#F5E642"/><rect x="20" y="23" width="15" height="12" rx="6" fill="none" stroke="#C8BC00" stroke-width="2"/><rect x="45" y="23" width="15" height="12" rx="6" fill="none" stroke="#C8BC00" stroke-width="2"/><line x1="35" y1="29" x2="45" y2="29" stroke="#C8BC00" stroke-width="2"/><rect x="24" y="25" width="6" height="7" rx="3" fill="#1A1A1A"/><rect x="49" y="25" width="6" height="7" rx="3" fill="#1A1A1A"/><rect x="25" y="26" width="3" height="3" rx="1.5" fill="white"/><rect x="50" y="26" width="3" height="3" rx="1.5" fill="white"/><path d="M33 38 Q42 41 49 37" stroke="#C8BC00" stroke-width="2" stroke-linecap="round" fill="none"/><ellipse cx="21" cy="36" rx="5" ry="3" fill="#E8DC00" opacity="0.4"/><ellipse cx="59" cy="36" rx="5" ry="3" fill="#E8DC00" opacity="0.4"/><rect x="4" y="44" width="16" height="10" rx="5" fill="#C8BC00"/><rect x="2" y="30" width="15" height="20" rx="3" fill="#222" stroke="#F5E642" stroke-width="0.8" opacity="0.9"/><path d="M6 37 L8 40 L13 34" stroke="#4ADE80" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/><path d="M6 43 L8 46 L13 40" stroke="#4ADE80" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/><g><animateTransform attributeName="transform" type="rotate" values="0 60 47;-22 60 47;0 60 47;8 60 47;0 60 47" dur="0.8s" repeatCount="indefinite"/><rect x="60" y="42" width="16" height="10" rx="5" fill="#C8BC00"/></g><rect x="24" y="70" width="12" height="22" rx="6" fill="#C8BC00"/><rect x="44" y="70" width="12" height="22" rx="6" fill="#C8BC00"/><rect x="20" y="86" width="16" height="8" rx="4" fill="#A89C00"/><rect x="44" y="86" width="16" height="8" rx="4" fill="#A89C00"/></g></svg>`,
  'db-architect': `<svg width="48" height="56" viewBox="0 0 90 100" fill="none"><g><animateTransform attributeName="transform" type="translate" values="0,0;0,-3;0,0" dur="0.7s" repeatCount="indefinite"/><ellipse cx="40" cy="97" rx="20" ry="3.5" fill="#4A9EFF" opacity="0.1"/><rect x="18" y="40" width="44" height="34" rx="10" fill="#1A6FCC"/><ellipse cx="40" cy="48" rx="10" ry="4" fill="#4A9EFF" opacity="0.5"/><rect x="30" y="48" width="20" height="8" fill="#4A9EFF" opacity="0.3"/><ellipse cx="40" cy="56" rx="10" ry="4" fill="#4A9EFF" opacity="0.4"/><rect x="14" y="8" width="52" height="46" rx="22" fill="#4A9EFF"/><rect x="12" y="14" width="56" height="12" rx="6" fill="#1A6FCC"/><rect x="8" y="18" width="64" height="8" rx="4" fill="#2A7FDD"/><rect x="22" y="26" width="10" height="11" rx="5" fill="#1A1A1A"/><rect x="48" y="26" width="10" height="11" rx="5" fill="#1A1A1A"/><rect x="25" y="27" width="4" height="5" rx="2" fill="white"/><rect x="51" y="27" width="4" height="5" rx="2" fill="white"/><path d="M31 39 Q40 44 49 39" stroke="#1A6FCC" stroke-width="2" stroke-linecap="round" fill="none"/><ellipse cx="21" cy="37" rx="5" ry="3" fill="#6AB4FF" opacity="0.4"/><ellipse cx="59" cy="37" rx="5" ry="3" fill="#6AB4FF" opacity="0.4"/><rect x="4" y="44" width="16" height="10" rx="5" fill="#1A6FCC"/><g><animateTransform attributeName="transform" type="rotate" values="0 60 49;-20 60 49;0 60 49;8 60 49;0 60 49" dur="0.8s" repeatCount="indefinite"/><rect x="60" y="44" width="16" height="10" rx="5" fill="#1A6FCC"/><rect x="63" y="28" width="4" height="22" rx="2" fill="#8B7355"/><rect x="58" y="42" width="14" height="10" rx="3" fill="#4A9EFF" opacity="0.8"/></g><rect x="24" y="70" width="12" height="22" rx="6" fill="#1A6FCC"/><rect x="44" y="70" width="12" height="22" rx="6" fill="#1A6FCC"/><rect x="20" y="86" width="16" height="8" rx="4" fill="#0A4F9A"/><rect x="44" y="86" width="16" height="8" rx="4" fill="#0A4F9A"/></g></svg>`,
  'backend-dev': `<svg width="48" height="56" viewBox="0 0 90 100" fill="none"><g><animateTransform attributeName="transform" type="translate" values="0,0;0,-3;0,0" dur="0.7s" repeatCount="indefinite"/><ellipse cx="40" cy="97" rx="20" ry="3.5" fill="#00D4FF" opacity="0.1"/><rect x="16" y="40" width="48" height="34" rx="12" fill="#008BAA"/><rect x="26" y="56" width="28" height="14" rx="4" fill="#007A99" opacity="0.7"/><rect x="10" y="48" width="28" height="18" rx="3" fill="#1A1A1A" stroke="#00D4FF" stroke-width="0.8"/><rect x="11" y="49" width="26" height="14" rx="2" fill="#0A2A30"/><rect x="13" y="51" width="14" height="1.5" rx="1" fill="#00D4FF" opacity="0.7"/><rect x="13" y="54" width="10" height="1.5" rx="1" fill="#4ADE80" opacity="0.6"/><rect x="13" y="57" width="18" height="1.5" rx="1" fill="#00D4FF" opacity="0.5"/><rect x="13" y="60" width="8" height="1.5" rx="1" fill="#F5E642" opacity="0.5"/><rect x="8" y="66" width="32" height="3" rx="1.5" fill="#2A2A2A"/><rect x="14" y="8" width="52" height="46" rx="22" fill="#00D4FF"/><rect x="22" y="24" width="10" height="11" rx="5" fill="#1A1A1A"/><rect x="48" y="24" width="10" height="11" rx="5" fill="#1A1A1A"/><rect x="25" y="25" width="4" height="5" rx="2" fill="white"/><rect x="51" y="25" width="4" height="5" rx="2" fill="white"/><path d="M33 38 Q40 42 47 38" stroke="#008BAA" stroke-width="2" stroke-linecap="round" fill="none"/><ellipse cx="21" cy="36" rx="5" ry="3" fill="#00C8EE" opacity="0.4"/><ellipse cx="59" cy="36" rx="5" ry="3" fill="#00C8EE" opacity="0.4"/><rect x="4" y="52" width="14" height="10" rx="5" fill="#008BAA"/><g><animateTransform attributeName="transform" type="rotate" values="0 62 49;-20 62 49;0 62 49;8 62 49;0 62 49" dur="0.8s" repeatCount="indefinite"/><rect x="62" y="44" width="14" height="10" rx="5" fill="#008BAA"/></g><rect x="24" y="70" width="12" height="22" rx="6" fill="#008BAA"/><rect x="44" y="70" width="12" height="22" rx="6" fill="#008BAA"/><rect x="20" y="86" width="16" height="8" rx="4" fill="#006688"/><rect x="44" y="86" width="16" height="8" rx="4" fill="#006688"/></g></svg>`,
  'frontend-dev': `<svg width="48" height="56" viewBox="0 0 90 100" fill="none"><g><animateTransform attributeName="transform" type="translate" values="0,0;0,-3;0,0" dur="0.7s" repeatCount="indefinite"/><ellipse cx="40" cy="97" rx="20" ry="3.5" fill="#FF7B6B" opacity="0.1"/><rect x="18" y="40" width="44" height="34" rx="10" fill="#CC4A3A"/><ellipse cx="32" cy="57" rx="10" ry="7" fill="#AA3028" opacity="0.7"/><circle cx="28" cy="55" r="2.5" fill="#F5E642"/><circle cx="34" cy="52" r="2.5" fill="#4ADE80"/><circle cx="38" cy="57" r="2.5" fill="#4A9EFF"/><rect x="14" y="8" width="52" height="46" rx="22" fill="#FF7B6B"/><ellipse cx="40" cy="11" rx="22" ry="8" fill="#CC4A3A"/><ellipse cx="52" cy="9" rx="8" ry="5" fill="#CC4A3A"/><circle cx="56" cy="7" r="3" fill="#FF9B8B"/><path d="M22 27 Q27 23 32 27" stroke="#1A1A1A" stroke-width="3" stroke-linecap="round" fill="none"/><path d="M48 27 Q53 23 58 27" stroke="#1A1A1A" stroke-width="3" stroke-linecap="round" fill="none"/><path d="M28 37 Q40 46 52 37" stroke="#CC4A3A" stroke-width="2.5" stroke-linecap="round" fill="none"/><ellipse cx="21" cy="34" rx="5" ry="3" fill="#FF9B8B" opacity="0.6"/><ellipse cx="59" cy="34" rx="5" ry="3" fill="#FF9B8B" opacity="0.6"/><rect x="4" y="44" width="16" height="10" rx="5" fill="#CC4A3A"/><g><animateTransform attributeName="transform" type="rotate" values="0 60 49;-22 60 49;0 60 49;8 60 49;0 60 49" dur="0.8s" repeatCount="indefinite"/><rect x="60" y="44" width="16" height="10" rx="5" fill="#CC4A3A"/><rect x="58" y="30" width="4" height="24" rx="2" fill="#8B7355" transform="rotate(20 60 42)"/><ellipse cx="63" cy="29" rx="4" ry="5" fill="#FF7B6B" transform="rotate(20 63 32)"/></g><rect x="24" y="70" width="12" height="22" rx="6" fill="#CC4A3A"/><rect x="44" y="70" width="12" height="22" rx="6" fill="#CC4A3A"/><rect x="20" y="86" width="16" height="8" rx="4" fill="#AA2A1A"/><rect x="44" y="86" width="16" height="8" rx="4" fill="#AA2A1A"/></g></svg>`,
  debugger: `<svg width="48" height="56" viewBox="0 0 90 100" fill="none"><g><animateTransform attributeName="transform" type="translate" values="0,0;0,-2;0,1;0,-1;0,0" dur="0.4s" repeatCount="indefinite"/><ellipse cx="40" cy="97" rx="20" ry="3.5" fill="#FF8C2B" opacity="0.1"/><line x1="2" y1="44" x2="13" y2="44" stroke="#FF8C2B" stroke-width="2" stroke-linecap="round" opacity="0.45"/><line x1="1" y1="51" x2="11" y2="51" stroke="#FF8C2B" stroke-width="2" stroke-linecap="round" opacity="0.3"/><line x1="3" y1="58" x2="12" y2="58" stroke="#FF8C2B" stroke-width="2" stroke-linecap="round" opacity="0.18"/><rect x="20" y="42" width="42" height="32" rx="10" fill="#CC5500"/><rect x="15" y="8" width="50" height="46" rx="22" fill="#FF8C2B"/><rect x="21" y="22" width="12" height="13" rx="6" fill="#1A1A1A"/><rect x="47" y="22" width="12" height="13" rx="6" fill="#1A1A1A"/><rect x="24" y="23" width="5" height="6" rx="2.5" fill="white"/><rect x="50" y="23" width="5" height="6" rx="2.5" fill="white"/><rect x="20" y="18" width="11" height="3" rx="1.5" fill="#CC5500" transform="rotate(10 25 19)"/><rect x="49" y="18" width="11" height="3" rx="1.5" fill="#CC5500" transform="rotate(-10 54 19)"/><ellipse cx="40" cy="39" rx="6" ry="5" fill="#1A1A1A"/><ellipse cx="40" cy="40" rx="4" ry="3" fill="#CC3300"/><rect x="4" y="48" width="18" height="9" rx="4" fill="#FF8C2B"/><g><animateTransform attributeName="transform" type="rotate" values="0 56 42;-15 56 42;0 56 42;10 56 42;0 56 42" dur="0.6s" repeatCount="indefinite"/><rect x="56" y="38" width="16" height="9" rx="4" fill="#FF8C2B"/><circle cx="74" cy="28" r="9" stroke="#FF8C2B" stroke-width="2.5" fill="rgba(255,140,43,0.08)"/><line x1="80" y1="34" x2="86" y2="40" stroke="#FF8C2B" stroke-width="3" stroke-linecap="round"/><circle cx="74" cy="28" r="3.5" fill="#FF4444"/></g><rect x="24" y="70" width="11" height="22" rx="5" fill="#CC5500" transform="rotate(12 29 81)"/><rect x="46" y="70" width="11" height="22" rx="5" fill="#CC5500" transform="rotate(-15 51 81)"/><rect x="18" y="84" width="15" height="7" rx="3.5" fill="#AA3300" transform="rotate(12 25 87)"/><rect x="47" y="82" width="15" height="7" rx="3.5" fill="#AA3300" transform="rotate(-15 54 85)"/></g></svg>`,
  security: `<svg width="48" height="56" viewBox="0 0 90 100" fill="none"><g><animateTransform attributeName="transform" type="translate" values="0,0;0,-3;0,0" dur="0.7s" repeatCount="indefinite"/><ellipse cx="40" cy="97" rx="22" ry="3.5" fill="#FF4444" opacity="0.12"/><rect x="14" y="38" width="52" height="36" rx="10" fill="#CC1111"/><path d="M28 44 L40 40 L52 44 L52 60 Q40 67 28 60 Z" fill="#FF4444" stroke="#FF6666" stroke-width="1"/><path d="M32 47 L40 44 L48 47 L48 58 Q40 63 32 58 Z" fill="#CC1111"/><path d="M35 53 L38 57 L46 48" stroke="#FF8080" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none"/><rect x="16" y="6" width="48" height="44" rx="20" fill="#FF4444"/><rect x="21" y="20" width="12" height="12" rx="5" fill="#1A1A1A"/><rect x="47" y="20" width="12" height="12" rx="5" fill="#1A1A1A"/><rect x="24" y="22" width="5" height="6" rx="2.5" fill="white"/><rect x="50" y="22" width="5" height="6" rx="2.5" fill="white"/><rect x="19" y="16" width="16" height="4" rx="2" fill="#AA1111"/><rect x="45" y="16" width="16" height="4" rx="2" fill="#AA1111"/><rect x="29" y="37" width="22" height="3.5" rx="1.75" fill="#AA1111"/><rect x="1" y="42" width="15" height="11" rx="5" fill="#FF4444"/><rect x="1" y="51" width="13" height="11" rx="4" fill="#CC1111"/><g><animateTransform attributeName="transform" type="rotate" values="0 64 47;-18 64 47;0 64 47;8 64 47;0 64 47" dur="0.8s" repeatCount="indefinite"/><rect x="64" y="42" width="15" height="11" rx="5" fill="#FF4444"/><rect x="66" y="51" width="13" height="11" rx="4" fill="#CC1111"/></g><rect x="19" y="70" width="14" height="22" rx="6" fill="#CC1111"/><rect x="47" y="70" width="14" height="22" rx="6" fill="#CC1111"/><rect x="13" y="86" width="18" height="8" rx="4" fill="#AA1111"/><rect x="49" y="86" width="18" height="8" rx="4" fill="#AA1111"/></g></svg>`,
  reviewer: `<svg width="48" height="56" viewBox="0 0 90 100" fill="none"><g><animateTransform attributeName="transform" type="translate" values="0,0;0,-3;0,0" dur="0.7s" repeatCount="indefinite"/><ellipse cx="40" cy="97" rx="20" ry="3.5" fill="#4ADE80" opacity="0.1"/><rect x="18" y="40" width="44" height="34" rx="10" fill="#1A8840"/><rect x="24" y="46" width="20" height="24" rx="3" fill="#148830" stroke="#4ADE80" stroke-width="0.5" opacity="0.7"/><rect x="26" y="50" width="16" height="1.5" rx="1" fill="#4ADE80" opacity="0.5"/><rect x="26" y="54" width="12" height="1.5" rx="1" fill="#4ADE80" opacity="0.4"/><rect x="26" y="58" width="14" height="1.5" rx="1" fill="#4ADE80" opacity="0.4"/><path d="M28 62 L30 65 L36 59" stroke="#4ADE80" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/><rect x="14" y="8" width="52" height="46" rx="22" fill="#4ADE80"/><rect x="19" y="24" width="16" height="11" rx="5" fill="none" stroke="#1A8840" stroke-width="2.5"/><rect x="45" y="24" width="16" height="11" rx="5" fill="none" stroke="#1A8840" stroke-width="2.5"/><line x1="35" y1="29" x2="45" y2="29" stroke="#1A8840" stroke-width="2.5"/><line x1="19" y1="29" x2="15" y2="27" stroke="#1A8840" stroke-width="2"/><line x1="61" y1="29" x2="65" y2="27" stroke="#1A8840" stroke-width="2"/><rect x="23" y="26" width="6" height="6" rx="3" fill="#1A1A1A"/><rect x="49" y="26" width="6" height="6" rx="3" fill="#1A1A1A"/><rect x="24" y="27" width="3" height="3" rx="1.5" fill="white"/><rect x="50" y="27" width="3" height="3" rx="1.5" fill="white"/><path d="M31 38 Q40 44 49 38" stroke="#1A8840" stroke-width="2.5" stroke-linecap="round" fill="none"/><ellipse cx="20" cy="36" rx="5" ry="3" fill="#6AEE90" opacity="0.4"/><ellipse cx="60" cy="36" rx="5" ry="3" fill="#6AEE90" opacity="0.4"/><rect x="4" y="44" width="16" height="10" rx="5" fill="#1A8840"/><g><animateTransform attributeName="transform" type="rotate" values="0 60 49;-20 60 49;0 60 49;8 60 49;0 60 49" dur="0.8s" repeatCount="indefinite"/><rect x="60" y="44" width="16" height="10" rx="5" fill="#1A8840"/></g><rect x="24" y="70" width="12" height="22" rx="6" fill="#1A8840"/><rect x="44" y="70" width="12" height="22" rx="6" fill="#1A8840"/><rect x="20" y="86" width="16" height="8" rx="4" fill="#0A6830"/><rect x="44" y="86" width="16" height="8" rx="4" fill="#0A6830"/></g></svg>`,
  devops: `<svg width="48" height="56" viewBox="0 0 90 100" fill="none"><g><animateTransform attributeName="transform" type="translate" values="0,0;0,-3;0,0" dur="0.7s" repeatCount="indefinite"/><ellipse cx="40" cy="97" rx="20" ry="3.5" fill="#A0A8B0" opacity="0.1"/><rect x="18" y="40" width="44" height="34" rx="10" fill="#606870"/><rect x="18" y="62" width="44" height="8" rx="2" fill="#505860"/><rect x="26" y="62" width="8" height="8" fill="#404850"/><rect x="40" y="62" width="8" height="8" fill="#404850"/><rect x="14" y="8" width="52" height="46" rx="22" fill="#A0A8B0"/><rect x="12" y="12" width="56" height="14" rx="7" fill="#606870"/><rect x="8" y="18" width="64" height="8" rx="4" fill="#707880"/><rect x="22" y="28" width="10" height="10" rx="5" fill="#1A1A1A"/><rect x="48" y="28" width="10" height="10" rx="5" fill="#1A1A1A"/><rect x="25" y="29" width="4" height="5" rx="2" fill="white"/><rect x="51" y="29" width="4" height="5" rx="2" fill="white"/><path d="M33 40 Q40 44 47 41" stroke="#606870" stroke-width="2" stroke-linecap="round" fill="none"/><ellipse cx="21" cy="38" rx="5" ry="3" fill="#B8C0C8" opacity="0.4"/><ellipse cx="59" cy="38" rx="5" ry="3" fill="#B8C0C8" opacity="0.4"/><rect x="4" y="44" width="16" height="10" rx="5" fill="#606870"/><g><animateTransform attributeName="transform" type="rotate" values="0 60 49;-18 60 49;0 60 49;8 60 49;0 60 49" dur="0.8s" repeatCount="indefinite"/><rect x="60" y="44" width="16" height="10" rx="5" fill="#606870"/><rect x="60" y="36" width="5" height="20" rx="2.5" fill="#808890" transform="rotate(25 62 46)"/><ellipse cx="63" cy="34" rx="6" ry="5" fill="none" stroke="#808890" stroke-width="3" transform="rotate(25 63 34)"/></g><rect x="24" y="70" width="12" height="22" rx="6" fill="#606870"/><rect x="44" y="70" width="12" height="22" rx="6" fill="#606870"/><rect x="20" y="86" width="16" height="8" rx="4" fill="#404850"/><rect x="44" y="86" width="16" height="8" rx="4" fill="#404850"/></g></svg>`
};

const AGENT_COLOR = {
  planner:'#D8D4CC', qa:'#F5E642', 'db-architect':'#4A9EFF',
  'backend-dev':'#00D4FF', 'frontend-dev':'#FF7B6B', debugger:'#FF8C2B',
  security:'#FF4444', reviewer:'#4ADE80', devops:'#A0A8B0'
};

const STAGE_AGENTS = [
  {stage:1,agent:'planner',label:'Planner'},{stage:2,agent:'qa',label:'QA'},
  {stage:3,agent:'db-architect',label:'DB Arch'},{stage:4,agent:'backend-dev',label:'Backend'},
  {stage:5,agent:'frontend-dev',label:'Frontend'},{stage:5.5,agent:'debugger',label:'Debugger'},
  {stage:6,agent:'security',label:'Security'},{stage:7,agent:'reviewer',label:'Reviewer'},
  {stage:8,agent:'devops',label:'DevOps'}
];

// ── PIPELINE PROGRESS ─────────────────────────────────────────────────────────
const progressEl = document.getElementById('pipeline-progress');

if (PROGRESS && PROGRESS.task) {
  const p = PROGRESS;
  // Auto-detect completion: Reviewer in stages + nothing running = done
  const hasReviewer = p.stages && (p.stages['Reviewer'] || p.stages['reviewer']);
  const hasRunning = p.stages && Object.values(p.stages).some(s => s.status === 'running');
  if (hasReviewer && !hasRunning && p.status !== 'completed') {
    p.status = 'completed';
    // Mark last running stage as done
    Object.values(p.stages).forEach(s => { if (s.status === 'running') s.status = 'done'; });
  }
  const pct = p.status === 'completed' ? 100 : Math.round((p.current_stage / p.total_stages) * 100);
  const statusColor = p.status === 'completed' ? 'var(--green)' : 'var(--yellow)';

  progressEl.innerHTML = `
    <div class="pipeline-task-name">${p.task}</div>
    <div class="pipeline-meta">
      <span style="color:${statusColor}">${p.status} · stage ${p.current_stage}/${p.total_stages}</span>
      <span>${p.mode || 'standard'} mode · started ${p.started || ''}</span>
    </div>
  `;

  const row = document.createElement('div');
  row.className = 'pipeline-agents-row';

  STAGE_AGENTS.forEach(({ stage, agent, label }) => {
    const stageInt = Math.floor(stage);
    // Match stage info by label, agent name, or capitalized agent name (e.g. "Backend-Dev")
    const agentCap = agent.split('-').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join('-');
    const stageInfo = p.stages ? (p.stages[label] || p.stages[agent] || p.stages[agentCap]) : null;
    const isSkipped = stageInfo && stageInfo.status === 'skipped';
    if (isSkipped) return;

    // Only mark done if agent actually ran (appears in stages)
    let status = 'pending';
    if (stageInfo && stageInfo.status === 'done') status = 'done';
    else if (stageInfo && stageInfo.status === 'running') status = 'running';
    else if (p.current_stage > stageInt && stageInfo) status = 'done';

    const svg = AGENT_SVG[agent] || '';
    const color = AGENT_COLOR[agent] || '#888';

    const slot = document.createElement('div');
    slot.className = `pipeline-agent-slot ${status}`;
    slot.setAttribute('data-agent', agent);

    // Determine activity type for animations
    const agentActivities = {
      'planner': 'thinking', 'qa': 'typing', 'db-architect': 'thinking',
      'backend-dev': 'typing', 'frontend-dev': 'typing', 'debugger': 'reading',
      'security': 'shielding', 'reviewer': 'reviewing', 'devops': 'typing'
    };
    const activity = status === 'running' ? (agentActivities[agent] || 'typing') : '';
    if (activity) slot.setAttribute('data-activity', activity);

    const glowHtml = status === 'running' ? `<div class="glow-ring" style="background:radial-gradient(circle,${color}44 0%,transparent 60%);animation:glow-ring-pulse 1.5s ease-in-out infinite"></div>` : '';
    // Strip SMIL animations for non-running agents — they stay still
    const agentSvg = status === 'running' ? svg : svg.replace(/<animateTransform[^/]*\/>/g, '');
    // Get description for speech bubble
    const agentStageInfo = p.stages ? (p.stages[label] || p.stages[agent] || p.stages[label.replace(' ','-')] || {}) : {};
    const desc = agentStageInfo.description || '';
    // Short speech text based on agent
    const speechTexts = {
      'planner': 'Designing architecture...', 'qa': 'Writing tests...', 'db-architect': 'Designing schema...',
      'backend-dev': 'Implementing code...', 'frontend-dev': 'Building UI...', 'debugger': 'Investigating bug...',
      'security': 'Scanning for vulns...', 'reviewer': 'Reviewing code...', 'devops': 'Configuring infra...'
    };
    const doneSpeech = {
      'planner': 'PRD ready', 'qa': 'Tests written', 'db-architect': 'Schema done',
      'backend-dev': 'Code complete', 'frontend-dev': 'UI built', 'debugger': 'Bug fixed',
      'security': 'Audit clear', 'reviewer': 'Approved', 'devops': 'Deployed'
    };
    let speechHtml = '';
    if (status === 'running') {
      const speech = desc ? desc.split(' for: ')[0] : (speechTexts[agent] || 'Working...');
      speechHtml = `<div class="speech-bubble">${speech}</div>`;
    } else if (status === 'done') {
      speechHtml = `<div class="speech-bubble">${doneSpeech[agent] || 'Done'}</div>`;
    }

    slot.innerHTML = `
      ${speechHtml}
      <div class="check">✓</div>
      ${glowHtml}
      <div class="pipeline-agent-char ${status}" style="color:${color}">${agentSvg}</div>
      <div class="pipeline-agent-name" style="${status === 'running' ? 'color:'+color+';text-shadow:0 0 8px '+color : status === 'done' ? '' : 'color:#444'}">${label}</div>
    `;
    row.appendChild(slot);
  });

  progressEl.appendChild(row);

  const track = document.createElement('div');
  track.className = 'pipeline-track';
  track.innerHTML = `<div class="pipeline-track-fill" style="width:${pct}%;background:${statusColor}"></div>`;
  progressEl.appendChild(track);

  if (p.stages && Object.keys(p.stages).length > 0) {
    const list = document.createElement('div');
    list.className = 'stage-list';
    Object.entries(p.stages).forEach(([name, info]) => {
      const icon = info.status === 'done' ? '✓' : info.status === 'running' ? '→' : '○';
      const cls = `stage-icon-${info.status || 'pending'}`;
      const desc = info.description ? `<span style="color:var(--text-dim);font-size:11px;margin-left:8px">${info.description}</span>` : '';
      const files = [];
      if (info.files_created && info.files_created.length) files.push(`${info.files_created.length} created`);
      if (info.files_edited && info.files_edited.length) files.push(`${info.files_edited.length} edited`);
      if (info.tests_run) files.push(`${info.tests_run} tests`);
      const filesBadge = files.length ? `<span style="color:var(--text-dim);font-size:10px;margin-left:8px">${files.join(', ')}</span>` : '';
      list.innerHTML += `<div class="stage-row"><span class="${cls}">${icon} ${name}${desc}${filesBadge}</span><span class="stage-time">${info.time || ''}</span></div>`;
    });
    progressEl.appendChild(list);
  }
} else {
  progressEl.innerHTML = `<div style="color:var(--text-dim);font-size:12px;margin-bottom:14px;text-align:center">No pipeline running — all agents standing by</div>`;
  const row = document.createElement('div');
  row.className = 'pipeline-agents-row';
  STAGE_AGENTS.forEach(({ agent, label }) => {
    const svg = AGENT_SVG[agent] || '';
    const color = AGENT_COLOR[agent] || '#888';
    const slot = document.createElement('div');
    slot.className = 'pipeline-agent-slot pending';
    const staticSvg = svg.replace(/<animateTransform[^/]*\/>/g, '');
    slot.innerHTML = `<div class="pipeline-agent-char pending" style="color:${color}">${staticSvg}</div><div class="pipeline-agent-name" style="color:#444">${label}</div>`;
    row.appendChild(slot);
  });
  progressEl.appendChild(row);
}

// ── KNOWLEDGE GRAPH ───────────────────────────────────────────────────────────
const typeColors = {
  agents:'#58a6ff', skills:'#bc8cff', bugs:'#f85149',
  heuristics:'#d29922', lessons:'#3fb950', architecture:'#39d2c0',
  tools:'#f0883e', decisions:'#8b949e', stack:'#ff7b72'
};
const visibleTypes = new Set();
const legendEl = document.getElementById('graph-legend');
Object.entries(typeColors).forEach(([type, color]) => {
  if (GRAPH.nodes.some(n => n.type === type)) {
    visibleTypes.add(type);
    const item = document.createElement('div');
    item.className = 'legend-item active';
    item.dataset.type = type;
    item.innerHTML = `<div class="legend-dot" style="background:${color}"></div>${type}`;
    item.addEventListener('click', () => {
      if (visibleTypes.has(type)) { visibleTypes.delete(type); item.classList.remove('active'); item.classList.add('hidden'); }
      else { visibleTypes.add(type); item.classList.add('active'); item.classList.remove('hidden'); }
      updateGraphVisibility();
    });
    legendEl.appendChild(item);
  }
});

const container = document.getElementById('graph');
const width = container.clientWidth, height = 450;
const svg = d3.select('#graph').append('svg').attr('width', width).attr('height', height).style('cursor','grab');
const zoomG = svg.append('g');
const zoom = d3.zoom().scaleExtent([0.2, 5]).on('zoom', e => zoomG.attr('transform', e.transform));
svg.call(zoom);
svg.on('dblclick.zoom', () => svg.transition().duration(500).call(zoom.transform, d3.zoomIdentity));
svg.append('text').attr('x', width-10).attr('y', height-10).attr('text-anchor','end').attr('fill','#30363d').attr('font-size','10px').text('Scroll to zoom · Drag to pan · Double-click to reset');

const simulation = d3.forceSimulation(GRAPH.nodes)
  .force('link', d3.forceLink(GRAPH.edges).id(d => d.id).distance(80))
  .force('charge', d3.forceManyBody().strength(-200))
  .force('center', d3.forceCenter(width/2, height/2))
  .force('collision', d3.forceCollide().radius(25));

const linkG = zoomG.append('g'), nodeG = zoomG.append('g'), labelG = zoomG.append('g');
const link = linkG.selectAll('line').data(GRAPH.edges).join('line').attr('stroke','#30363d').attr('stroke-width',1);
// Tooltip
const tooltip = d3.select('#graph').append('div')
  .style('position','absolute').style('display','none').style('pointer-events','none')
  .style('background','var(--surface)').style('border','1px solid var(--border)')
  .style('border-radius','8px').style('padding','10px 14px').style('font-size','12px')
  .style('color','var(--text)').style('box-shadow','0 4px 12px rgba(0,0,0,0.3)')
  .style('z-index','10').style('max-width','250px');

const node = nodeG.selectAll('circle').data(GRAPH.nodes).join('circle')
  .attr('r', d => d.type === 'agents' ? 14 : 9)
  .attr('fill', d => typeColors[d.type] || '#8b949e')
  .attr('stroke','#0d1117').attr('stroke-width',2).style('cursor','pointer')
  .on('click', (e, d) => highlightNode(d))
  .on('mouseenter', (e, d) => {
    const connections = GRAPH.edges.filter(edge => {
      const s = typeof edge.source==='object'?edge.source.id:edge.source;
      const t = typeof edge.target==='object'?edge.target.id:edge.target;
      return s===d.id || t===d.id;
    }).length;
    const color = typeColors[d.type] || '#8b949e';
    tooltip.style('display','block')
      .html(`<div style="font-weight:600;color:${color};margin-bottom:4px">${d.id}</div>
        <div style="color:var(--text-dim);font-size:11px">Type: ${d.type}</div>
        <div style="color:var(--text-dim);font-size:11px">Connections: ${connections}</div>
        ${d.summary ? '<div style="margin-top:4px;font-size:11px;color:var(--text-dim);border-top:1px solid var(--border);padding-top:4px">'+d.summary+'</div>' : ''}
        <div style="margin-top:6px;font-size:10px;color:var(--border)">Click to highlight · Drag to move</div>`);
  })
  .on('mousemove', (e) => {
    const rect = container.getBoundingClientRect();
    tooltip.style('left', (e.clientX - rect.left + 15) + 'px').style('top', (e.clientY - rect.top - 10) + 'px');
  })
  .on('mouseleave', () => tooltip.style('display','none'))
  .call(d3.drag().on('start', (e,d) => { if(!e.active) simulation.alphaTarget(0.3).restart(); d.fx=d.x; d.fy=d.y; })
    .on('drag', (e,d) => { d.fx=e.x; d.fy=e.y; tooltip.style('display','none'); })
    .on('end', (e,d) => { if(!e.active) simulation.alphaTarget(0); d.fx=null; d.fy=null; }));
const label = labelG.selectAll('text').data(GRAPH.nodes).join('text').text(d=>d.id).attr('dx',16).attr('dy',4).attr('font-size','11px').attr('fill','#8b949e');

let selectedNode = null;
function highlightNode(d) {
  if (selectedNode === d.id) { selectedNode = null; resetHighlight(); return; }
  selectedNode = d.id;
  const connected = new Set([d.id]);
  GRAPH.edges.forEach(e => { const s=typeof e.source==='object'?e.source.id:e.source, t=typeof e.target==='object'?e.target.id:e.target; if(s===d.id) connected.add(t); if(t===d.id) connected.add(s); });
  node.transition().duration(200).attr('opacity', n => connected.has(n.id) ? 1 : 0.08).attr('r', n => n.id===d.id ? 18 : (n.type==='agents'?14:9));
  label.transition().duration(200).attr('opacity', n => connected.has(n.id) ? 1 : 0.05).attr('fill', n => n.id===d.id ? '#fff' : '#8b949e').attr('font-weight', n => n.id===d.id ? 'bold' : 'normal');
  link.transition().duration(200)
    .attr('opacity', e => { const s=typeof e.source==='object'?e.source.id:e.source, t=typeof e.target==='object'?e.target.id:e.target; return (s===d.id||t===d.id)?1:0.03; })
    .attr('stroke', e => { const s=typeof e.source==='object'?e.source.id:e.source, t=typeof e.target==='object'?e.target.id:e.target; return (s===d.id||t===d.id)?typeColors[d.type]||'#58a6ff':'#30363d'; })
    .attr('stroke-width', e => { const s=typeof e.source==='object'?e.source.id:e.source, t=typeof e.target==='object'?e.target.id:e.target; return (s===d.id||t===d.id)?2.5:1; });
}
function resetHighlight() {
  node.transition().duration(200).attr('opacity',1).attr('r',d=>d.type==='agents'?14:9);
  label.transition().duration(200).attr('opacity',1).attr('fill','#8b949e').attr('font-weight','normal');
  link.transition().duration(200).attr('opacity',0.6).attr('stroke','#30363d').attr('stroke-width',1);
}
svg.on('click', e => { if(e.target.tagName==='svg'||e.target.tagName==='rect'){ selectedNode=null; resetHighlight(); } });
simulation.on('tick', () => {
  link.attr('x1',d=>d.source.x).attr('y1',d=>d.source.y).attr('x2',d=>d.target.x).attr('y2',d=>d.target.y);
  node.attr('cx',d=>d.x).attr('cy',d=>d.y);
  label.attr('x',d=>d.x).attr('y',d=>d.y);
});
function updateGraphVisibility() {
  node.attr('opacity',d=>visibleTypes.has(d.type)?1:0.05).attr('pointer-events',d=>visibleTypes.has(d.type)?'all':'none');
  label.attr('opacity',d=>visibleTypes.has(d.type)?1:0);
  link.attr('opacity',d=>{ const st=typeof d.source==='object'?d.source.type:GRAPH.nodes.find(n=>n.id===d.source)?.type, tt=typeof d.target==='object'?d.target.type:GRAPH.nodes.find(n=>n.id===d.target)?.type; return (visibleTypes.has(st)&&visibleTypes.has(tt))?0.6:0.03; });
}

// ── HEALTH SCORE ──────────────────────────────────────────────────────────────
const healthEl = document.getElementById('health-score');
const total = Object.values(HEALTH).reduce((a,b)=>a+b,0);
healthEl.textContent = total;
healthEl.style.color = total>=80?'var(--green)':total>=50?'var(--yellow)':'var(--red)';
const bar = document.getElementById('health-bar');
for(let i=0;i<20;i++){const cls=(i*5)<total?(total>=80?'active':'warn'):'empty';bar.innerHTML+=`<div class="block ${cls}"></div>`;}
const bd = document.getElementById('health-breakdown');
Object.entries(HEALTH).forEach(([k,v])=>{bd.innerHTML+=`<div class="breakdown-item"><span class="label">${k}</span><span>${v}</span></div>`;});

// ── STATS ─────────────────────────────────────────────────────────────────────
const statsEl = document.getElementById('stats');
const totalRuns = HISTORY.length;
const totalCost = HISTORY.reduce((a,h)=>a+(h.cost||0),0).toFixed(2);
const avgScore = HISTORY.length?(HISTORY.reduce((a,h)=>a+h.score,0)/HISTORY.length).toFixed(1):'0';
const agentSet = new Set(); HISTORY.forEach(h=>h.agents.forEach(a=>agentSet.add(a)));
[{value:totalRuns,label:'Pipeline Runs'},{value:'$'+totalCost,label:'Total Cost'},{value:avgScore,label:'Avg Complexity'},{value:agentSet.size,label:'Active Agents'}]
  .forEach(s=>{statsEl.innerHTML+=`<div class="stat"><div class="value">${s.value}</div><div class="label">${s.label}</div></div>`;});

// ── COST TABLE ────────────────────────────────────────────────────────────────
const thinkingAgents = new Set(['planner','security','reviewer']);
const modelFor = a => thinkingAgents.has(a)?'opus':'sonnet';
const TOKEN_EST = { opus:{input:4000,output:3000}, sonnet:{input:2000,output:1500} };
const PRICING = { opus:{input:15,output:75}, sonnet:{input:3,output:15} };
function estimateTask(h) {
  let tI=0,tO=0,cost=0,details=[];
  h.agents.forEach(a=>{ const m=modelFor(a),i=TOKEN_EST[m].input,o=TOKEN_EST[m].output; tI+=i; tO+=o; const c=(i*PRICING[m].input+o*PRICING[m].output)/1000000; cost+=c; details.push({agent:a,model:m,cost:c,total:i+o}); });
  return {totalInput:tI,totalOutput:tO,total:tI+tO,cost,details};
}
const costBody=document.getElementById('cost-body'), costFooter=document.getElementById('cost-footer');
const maxTokens=Math.max(...HISTORY.map(h=>estimateTask(h).total),1);
let runningCost=0,totalTokensAll=0;
HISTORY.forEach(h=>{
  const est=estimateTask(h); runningCost+=est.cost; totalTokensAll+=est.total;
  const bw=Math.round((est.total/maxTokens)*80);
  const ad=est.details.map(d=>{const mc=d.model==='opus'?'var(--purple)':'var(--cyan)';return `<span style="color:${mc}" title="${d.agent}:${d.model}·$${d.cost.toFixed(3)}">${d.agent}</span>`;}).join('<span style="color:var(--border)">→</span>');
  costBody.innerHTML+=`<tr><td style="padding:10px;max-width:220px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${h.task}</td><td style="padding:10px"><span class="mode-badge mode-${h.mode}">${h.mode}</span></td><td style="padding:10px;text-align:center">${h.score}/10</td><td style="padding:10px;font-size:11px">${ad}</td><td style="padding:10px;text-align:right;white-space:nowrap"><span class="token-bar" style="width:${bw}px"></span>${(est.total/1000).toFixed(1)}K</td><td style="padding:10px;text-align:right;font-weight:600;color:var(--accent)">$${est.cost.toFixed(3)}</td></tr>`;
});
costFooter.innerHTML=`<tr style="border-top:2px solid var(--border)"><td style="padding:10px;font-weight:600" colspan="3">Total (${HISTORY.length} tasks)</td><td style="padding:10px;font-size:11px;color:var(--text-dim)"><span style="color:var(--purple)">●</span> opus: thinking &nbsp;<span style="color:var(--cyan)">●</span> sonnet: execution</td><td style="padding:10px;text-align:right;color:var(--text-dim)">${(totalTokensAll/1000).toFixed(1)}K</td><td style="padding:10px;text-align:right;font-weight:700;color:var(--green);font-size:16px">$${runningCost.toFixed(2)}</td></tr>`;

// ── CHARTS ────────────────────────────────────────────────────────────────────
const agentCounts={};
HISTORY.forEach(h=>h.agents.forEach(a=>{agentCounts[a]=(agentCounts[a]||0)+1;}));
const sortedAgents=Object.entries(agentCounts).sort((a,b)=>b[1]-a[1]);
new Chart(document.getElementById('agent-chart'),{type:'bar',data:{labels:sortedAgents.map(a=>a[0]),datasets:[{data:sortedAgents.map(a=>a[1]),backgroundColor:'rgba(88,166,255,0.7)',borderRadius:3}]},options:{responsive:true,maintainAspectRatio:false,plugins:{legend:{display:false}},scales:{y:{ticks:{color:'#8b949e'},grid:{color:'#21262d'}},x:{ticks:{color:'#8b949e'},grid:{display:false}}}}});

const modeCounts={fast:0,standard:0,serious:0};
HISTORY.forEach(h=>{if(modeCounts[h.mode]!==undefined)modeCounts[h.mode]++;});
new Chart(document.getElementById('mode-chart'),{type:'doughnut',data:{labels:Object.keys(modeCounts),datasets:[{data:Object.values(modeCounts),backgroundColor:['#3fb950','#d29922','#f85149']}]},options:{responsive:true,maintainAspectRatio:false,plugins:{legend:{labels:{color:'#8b949e'}}}}});

const costData=HISTORY.map((h,i)=>({x:i+1,y:HISTORY.slice(0,i+1).reduce((a,b)=>a+(b.cost||0),0)}));
new Chart(document.getElementById('cost-chart'),{type:'line',data:{labels:costData.map(d=>d.x),datasets:[{data:costData.map(d=>d.y.toFixed(2)),borderColor:'#58a6ff',tension:0.3,fill:true,backgroundColor:'rgba(88,166,255,0.1)'}]},options:{responsive:true,maintainAspectRatio:false,plugins:{legend:{display:false}},scales:{y:{ticks:{color:'#8b949e',callback:v=>'$'+v},grid:{color:'#21262d'}},x:{ticks:{color:'#8b949e'},grid:{display:false}}}}});

const scoreBuckets=Array(10).fill(0);
HISTORY.forEach(h=>{if(h.score>=1&&h.score<=10)scoreBuckets[h.score-1]++;});
new Chart(document.getElementById('complexity-chart'),{type:'bar',data:{labels:['1','2','3','4','5','6','7','8','9','10'],datasets:[{data:scoreBuckets,backgroundColor:scoreBuckets.map((_,i)=>i<3?'#3fb950':i<6?'#d29922':'#f85149'),borderRadius:3}]},options:{responsive:true,maintainAspectRatio:false,plugins:{legend:{display:false}},scales:{y:{ticks:{color:'#8b949e'},grid:{color:'#21262d'}},x:{ticks:{color:'#8b949e'},grid:{display:false}}}}});

// ── TIMELINE ──────────────────────────────────────────────────────────────────
const tl=document.getElementById('timeline');
HISTORY.slice(-10).reverse().forEach(h=>{tl.innerHTML+=`<li><span class="time">${h.date}</span><div><div>${h.task}</div><div class="agents">${h.mode} · score ${h.score} · ${h.agents.join(' → ')}</div></div></li>`;});
if(HISTORY.length===0) tl.innerHTML='<li style="color:var(--text-dim)">No pipeline history yet.</li>';

// ── RAG DEEP MEMORY (Interactive Explorer) ────────────────────────────────────
const ragStats = document.getElementById('rag-stats');
const ragEntries = document.getElementById('rag-entries');
const ragSearch = document.getElementById('rag-search');
const ragFilter = document.getElementById('rag-filter');
const ragDetail = document.getElementById('rag-detail');
const ragDetailTitle = document.getElementById('rag-detail-title');
const ragDetailMeta = document.getElementById('rag-detail-meta');
const ragDetailContent = document.getElementById('rag-detail-content');

const ragTypeColors = {vault:'var(--green)',schema:'var(--cyan)',api:'var(--yellow)',plan:'var(--purple, #bc8cff)',commit:'var(--text-dim)',config:'var(--text-dim)',memories:'var(--green)'};
const ragTypeIcons = {vault:'🧠',schema:'🗄️',api:'🔌',plan:'📋',commit:'📝',config:'⚙️',memories:'🧠'};

function renderRagEntries(entries) {
  ragEntries.innerHTML = '';
  if (entries.length === 0) {
    ragEntries.innerHTML = '<div style="color:var(--text-dim);text-align:center;padding:20px;font-size:13px">No matches found.</div>';
    return;
  }
  entries.forEach((e, i) => {
    const tc = ragTypeColors[e.type] || 'var(--text-dim)';
    const icon = ragTypeIcons[e.type] || '•';
    const div = document.createElement('div');
    div.style.cssText = 'padding:6px 8px;border-bottom:1px solid var(--border);display:flex;gap:8px;align-items:center;cursor:pointer;border-radius:4px;transition:background 0.1s';
    div.innerHTML = `<span style="color:${tc};font-family:monospace;font-size:10px;min-width:55px">${icon} ${e.type}</span><span style="color:var(--text);flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${e.name}</span><span style="color:var(--text-dim);font-size:10px">${e.tags||''}</span><span style="color:var(--border);font-size:10px">▸</span>`;
    div.addEventListener('mouseenter', () => div.style.background = 'rgba(88,166,255,0.05)');
    div.addEventListener('mouseleave', () => div.style.background = 'transparent');
    div.addEventListener('click', () => showRagDetail(e));
    ragEntries.appendChild(div);
  });
}

function showRagDetail(entry) {
  ragDetail.style.display = 'block';
  ragDetailTitle.textContent = entry.name;
  ragDetailTitle.style.color = ragTypeColors[entry.type] || 'var(--text)';
  ragDetailMeta.innerHTML = `<span style="color:${ragTypeColors[entry.type]||'var(--text-dim)'}">${ragTypeIcons[entry.type]||'•'} ${entry.type}</span>${entry.tags ? ' · <span>'+entry.tags+'</span>' : ''}${entry.id ? ' · <span style="font-family:monospace">'+entry.id+'</span>' : ''}`;
  ragDetailContent.textContent = entry.content || entry.text || 'No content available';
  ragDetail.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

if (RAG && RAG.entries && RAG.entries.length > 0) {
  // Stats
  const typeCounts = {};
  RAG.entries.forEach(e => { typeCounts[e.type] = (typeCounts[e.type] || 0) + 1; });
  Object.entries(typeCounts).forEach(([type, count]) => {
    const stat = document.createElement('div');
    stat.style.cssText = 'text-align:center;cursor:pointer;padding:8px;border-radius:6px;transition:background 0.1s';
    stat.innerHTML = `<div style="font-size:24px;font-weight:700;color:${ragTypeColors[type]||'var(--text)'}">${count}</div><div style="font-size:10px;color:var(--text-dim)">${ragTypeIcons[type]||'•'} ${type}</div>`;
    stat.addEventListener('click', () => { ragFilter.value = type; filterRag(); });
    stat.addEventListener('mouseenter', () => stat.style.background = 'rgba(88,166,255,0.05)');
    stat.addEventListener('mouseleave', () => stat.style.background = 'transparent');
    ragStats.appendChild(stat);
  });

  // Populate filter dropdown
  Object.keys(typeCounts).forEach(type => {
    const opt = document.createElement('option');
    opt.value = type;
    opt.textContent = `${ragTypeIcons[type]||''} ${type} (${typeCounts[type]})`;
    ragFilter.appendChild(opt);
  });

  // Initial render
  renderRagEntries(RAG.entries);

  // Search + filter
  function filterRag() {
    const query = ragSearch.value.toLowerCase();
    const type = ragFilter.value;
    const filtered = RAG.entries.filter(e => {
      const matchType = type === 'all' || e.type === type;
      const matchQuery = !query || (e.name||'').toLowerCase().includes(query) || (e.content||'').toLowerCase().includes(query) || (e.tags||'').toLowerCase().includes(query);
      return matchType && matchQuery;
    });
    renderRagEntries(filtered);
    ragDetail.style.display = 'none';
  }

  ragSearch.addEventListener('input', filterRag);
  ragFilter.addEventListener('change', filterRag);

  // --- D3 Treemap ---
  const treemapEl = document.getElementById('rag-treemap');
  if (treemapEl) {
    const tmWidth = treemapEl.clientWidth || 400;
    const tmHeight = 220;

    const tmColorMap = {
      vault:'#3fb950', memories:'#3fb950', agents:'#58a6ff',
      schema:'#39d2c0', api:'#d29922', plan:'#bc8cff',
      commit:'#8b949e', config:'#f0883e', heuristics:'#d29922',
      tools:'#f0883e', stack:'#ff7b72'
    };

    // Build hierarchy: root → types → entries
    const typeGroups = {};
    RAG.entries.forEach(e => {
      if (!typeGroups[e.type]) typeGroups[e.type] = [];
      typeGroups[e.type].push(e);
    });

    const hierarchyData = {
      name: 'memory',
      children: Object.entries(typeGroups).map(([type, entries]) => ({
        name: type,
        children: entries.map(e => ({
          name: e.name,
          value: (e.content || e.tags || e.name || '').length + 10,
          type: e.type,
          entry: e
        }))
      }))
    };

    const root = d3.hierarchy(hierarchyData).sum(d => d.value).sort((a, b) => b.value - a.value);
    d3.treemap().size([tmWidth, tmHeight]).paddingOuter(3).paddingInner(2).round(true)(root);

    const tmSvg = d3.select('#rag-treemap').append('svg')
      .attr('width', tmWidth).attr('height', tmHeight);

    // Tooltip for treemap
    const tmTooltip = d3.select('#rag-treemap').append('div')
      .style('position','absolute').style('display','none').style('pointer-events','none')
      .style('background','var(--surface)').style('border','1px solid var(--border)')
      .style('border-radius','6px').style('padding','8px 12px').style('font-size','11px')
      .style('color','var(--text)').style('box-shadow','0 4px 12px rgba(0,0,0,0.4)').style('z-index','10');

    const leaves = tmSvg.selectAll('g').data(root.leaves()).join('g')
      .attr('transform', d => `translate(${d.x0},${d.y0})`);

    leaves.append('rect')
      .attr('width', d => Math.max(0, d.x1 - d.x0))
      .attr('height', d => Math.max(0, d.y1 - d.y0))
      .attr('rx', 3)
      .attr('fill', d => {
        const color = tmColorMap[d.data.type] || '#8b949e';
        return color + '33';
      })
      .attr('stroke', d => tmColorMap[d.data.type] || '#8b949e')
      .attr('stroke-width', 0.5)
      .attr('stroke-opacity', 0.4)
      .style('cursor', 'pointer')
      .on('mouseenter', (e, d) => {
        d3.select(e.target).attr('stroke-opacity', 1).attr('stroke-width', 1.5);
        const color = tmColorMap[d.data.type] || '#8b949e';
        tmTooltip.style('display','block')
          .html(`<div style="color:${color};font-weight:600;margin-bottom:2px">${d.data.name}</div><div style="color:var(--text-dim)">${d.data.type}</div>`);
      })
      .on('mousemove', (e) => {
        const rect = treemapEl.getBoundingClientRect();
        tmTooltip.style('left', (e.clientX - rect.left + 10)+'px').style('top', (e.clientY - rect.top - 30)+'px');
      })
      .on('mouseleave', (e) => {
        d3.select(e.target).attr('stroke-opacity', 0.4).attr('stroke-width', 0.5);
        tmTooltip.style('display','none');
      })
      .on('click', (e, d) => {
        if (d.data.entry) showRagDetail(d.data.entry);
      });

    // Labels for larger cells
    leaves.append('text')
      .attr('x', 4).attr('y', 13)
      .text(d => {
        const w = d.x1 - d.x0;
        if (w < 50) return '';
        const name = d.data.name;
        const maxChars = Math.floor(w / 6);
        return name.length > maxChars ? name.slice(0, maxChars - 1) + '…' : name;
      })
      .attr('font-size', '10px')
      .attr('fill', d => tmColorMap[d.data.type] || '#8b949e')
      .attr('fill-opacity', 0.8)
      .style('pointer-events', 'none');

    // Type labels for groups
    leaves.filter(d => (d.x1 - d.x0) > 40 && (d.y1 - d.y0) > 30)
      .append('text')
      .attr('x', 4).attr('y', d => Math.max(0, d.y1 - d.y0) - 5)
      .text(d => d.data.type)
      .attr('font-size', '8px')
      .attr('fill', 'var(--text-dim)')
      .attr('fill-opacity', 0.5)
      .style('pointer-events', 'none');
  }
} else {
  ragEntries.innerHTML = '<div style="color:var(--text-dim);text-align:center;padding:20px;font-size:13px">No RAG data. Run: tasuki vault sync</div>';
  ragSearch.style.display = 'none';
  ragFilter.style.display = 'none';
}

// ── ACTIVITY ──────────────────────────────────────────────────────────────────
const actEvents=(ACTIVITY.events||[]);
const impactEl=document.getElementById('activity-impact'), actLogEl=document.getElementById('activity-log');
if(actEvents.length>0){
  const counts={};
  actEvents.forEach(e=>{counts[e.type]=(counts[e.type]||0)+1;});
  [{type:'error_prevented',label:'Errors Prevented',icon:'🛡️',color:'var(--green)'},{type:'heuristic_loaded',label:'Heuristics Applied',icon:'📚',color:'var(--cyan)'},{type:'hook_blocked',label:'Unsafe Edits Blocked',icon:'🚫',color:'var(--yellow)'},{type:'pipeline_run',label:'Stages Run',icon:'⚙️',color:'var(--accent)'}]
    .forEach(imp=>{impactEl.innerHTML+=`<div style="text-align:center"><div style="font-size:28px;font-weight:700;color:${imp.color}">${counts[imp.type]||0}</div><div style="font-size:11px;color:var(--text-dim)">${imp.icon} ${imp.label}</div></div>`;});

  // Hook effectiveness breakdown
  const hookBlocks = actEvents.filter(e => e.type === 'hook_blocked');
  if (hookBlocks.length > 0) {
    const hookStats = {};
    hookBlocks.forEach(e => {
      const hook = e.agent || 'unknown';
      if (!hookStats[hook]) hookStats[hook] = { blocked: 0, detail: e.detail || '' };
      hookStats[hook].blocked++;
    });

    // Detect overrides: same hook + same detail within 120 seconds = override
    let overrides = 0;
    for (let i = 1; i < hookBlocks.length; i++) {
      const prev = hookBlocks[i-1], curr = hookBlocks[i];
      if (prev.agent === curr.agent && prev.detail === curr.detail) {
        const t1 = new Date(prev.time), t2 = new Date(curr.time);
        if ((t2 - t1) < 120000) overrides++;
      }
    }
    const accepted = hookBlocks.length - overrides;
    const effectiveness = hookBlocks.length > 0 ? Math.round((accepted / hookBlocks.length) * 100) : 100;

    let hookTable = '<div style="margin-top:12px;border-top:1px solid var(--border);padding-top:12px"><div style="font-size:12px;font-weight:600;color:var(--text);margin-bottom:8px">Hook Effectiveness</div>';
    hookTable += `<div style="display:flex;gap:16px;margin-bottom:8px;font-size:11px"><span style="color:var(--green)">Accepted: ${accepted}</span><span style="color:var(--red)">Overridden: ${overrides}</span><span style="color:var(--accent)">Effectiveness: ${effectiveness}%</span></div>`;
    hookTable += '<div style="font-size:11px">';
    Object.entries(hookStats).forEach(([hook, stats]) => {
      const color = stats.blocked > 3 ? 'var(--yellow)' : 'var(--text-dim)';
      hookTable += `<div style="display:flex;justify-content:space-between;padding:2px 0"><span style="color:${color}">${hook}</span><span style="color:var(--text-dim)">${stats.blocked} blocks</span></div>`;
    });
    hookTable += '</div></div>';
    impactEl.insertAdjacentHTML('afterend', hookTable);
  }

  const icons={heuristic_loaded:'📚',error_prevented:'🛡️',hook_blocked:'🚫',memory_read:'🧠',pipeline_run:'⚙️',bug_avoided:'🐛'};
  actEvents.slice(-15).reverse().forEach(e=>{const icon=icons[e.type]||'•', time=(e.time||'').slice(-8), agent=e.agent?` [${e.agent}]`:''; actLogEl.innerHTML+=`<div style="padding:4px 0;border-bottom:1px solid var(--border);font-size:12px;display:flex;gap:8px"><span style="color:var(--text-dim);min-width:60px">${time}</span><span>${icon}${agent} ${e.detail}</span></div>`;});
} else {
  actLogEl.innerHTML='<div style="color:var(--text-dim);text-align:center;padding:20px;font-size:13px">No activity recorded yet. Run some tasks to see impact.</div>';
}

// ── LIVE UPDATES (SSE) ────────────────────────────────────────────────────────
const liveDot = document.getElementById('live-dot');
function connectSSE() {
  const es = new EventSource('/events');
  es.onmessage = (e) => { if (e.data === 'reload') location.reload(); };
  es.onopen = () => { if (liveDot) { liveDot.classList.remove('disconnected'); liveDot.title = 'Live — watching for changes'; } };
  es.onerror = () => { if (liveDot) { liveDot.classList.add('disconnected'); liveDot.title = 'Disconnected — open via tasuki dashboard'; } es.close(); setTimeout(connectSSE, 5000); };
}
connectSSE();
</script>
</body>
</html>
JSEOF

  log_success "Dashboard generated: $output"

  # If called standalone (not from serve), open in browser
  if [ -z "${TASUKI_GENERATE_ONLY:-}" ]; then
    if command -v xdg-open &>/dev/null; then
      xdg-open "$output" 2>/dev/null &
    elif command -v open &>/dev/null; then
      open "$output" 2>/dev/null &
    else
      log_info "Open in browser: file://$output"
    fi
  fi
}

# --- Data extraction functions ---

extract_graph_data() {
  local project_dir="$1"
  local vault="$project_dir/memory-vault"

  if [ ! -d "$vault" ]; then
    echo '{"nodes":[],"edges":[]}'
    return
  fi

  # Use python for reliable JSON generation
  if command -v python3 &>/dev/null; then
    python3 << PYEOF
import os, re, json

vault = "$vault"
nodes = {}
edges = []

for root, dirs, files in os.walk(vault):
    for f in files:
        if not f.endswith('.md') or f == 'index.md':
            continue
        fpath = os.path.join(root, f)
        rel = os.path.relpath(fpath, vault)
        ntype = rel.split('/')[0]
        name = f.replace('.md', '')

        nodes[name] = {"id": name, "type": ntype}

        with open(fpath) as fh:
            content = fh.read()
        links = re.findall(r'\[\[([a-z0-9_-]+)\]\]', content)
        for link in set(links):
            edges.append({"source": name, "target": link})
            if link not in nodes:
                # guess type
                for t in ['agents','tools','heuristics','bugs','lessons','stack','decisions']:
                    if os.path.exists(os.path.join(vault, t, link + '.md')):
                        nodes[link] = {"id": link, "type": t}
                        break
                else:
                    nodes[link] = {"id": link, "type": "stack"}

print(json.dumps({"nodes": list(nodes.values()), "edges": edges}))
PYEOF
  else
    # Fallback: minimal
    echo '{"nodes":[],"edges":[]}'
  fi
}

extract_history_data() {
  local project_dir="$1"
  local history_file="$project_dir/.tasuki/config/pipeline-history.log"

  if [ ! -f "$history_file" ] || [ ! -s "$history_file" ]; then
    echo '[]'
    return
  fi

  echo "["
  local first=true
  while IFS='|' read -r date mode score agents duration task; do
    $first || echo ","
    first=false
    local agent_array
    agent_array=$(echo "$agents" | sed 's/,/","/g')
    local cost
    cost=$(echo "scale=3; $duration * 0.001" | bc 2>/dev/null || echo "0.05")
    # bc outputs .300 instead of 0.300 — fix for valid JSON
    [[ "$cost" == .* ]] && cost="0$cost"
    echo "{\"date\":\"$date\",\"mode\":\"$mode\",\"score\":$score,\"agents\":[\"$agent_array\"],\"cost\":$cost,\"task\":\"$task\"}"
  done < "$history_file"
  echo "]"
}

extract_health_data() {
  local project_dir="$1"

  # Quick inline health calculation
  local test_files source_files test_score=0
  test_files=$(find "$project_dir" -name "test_*" -o -name "*.test.*" -o -name "*.spec.*" 2>/dev/null | grep -cv node_modules 2>/dev/null) || test_files=0
  test_files=$(echo "$test_files" | tr -dc '0-9')
  test_files=${test_files:-0}
  source_files=$(find "$project_dir" \( -name "*.py" -o -name "*.ts" -o -name "*.js" -o -name "*.sh" \) -not -path "*/node_modules/*" -not -path "*/__pycache__/*" -not -path "*/.git/*" 2>/dev/null | wc -l | tr -dc '0-9')
  source_files=${source_files:-1}

  local ratio=$(( (test_files * 100) / (source_files + 1) ))
  if [ "$ratio" -ge 80 ]; then test_score=25
  elif [ "$ratio" -ge 50 ]; then test_score=20
  elif [ "$ratio" -ge 30 ]; then test_score=15
  elif [ "$ratio" -ge 10 ]; then test_score=10
  else test_score=5; fi

  local sec_score=18 doc_score=0 config_score=0 quality_score=13 infra_score=0

  [ -f "$project_dir/README.md" ] && doc_score=$((doc_score + 5))
  [ -f "$project_dir/TASUKI.md" ] && doc_score=$((doc_score + 4))
  [ -d "$project_dir/tasuki-plans" ] && doc_score=$((doc_score + 3))

  [ -d "$project_dir/.tasuki" ] && config_score=$((config_score + 3))
  [ -f "$project_dir/.tasuki/settings.json" ] && config_score=$((config_score + 2))
  [ -f "$project_dir/.mcp.json" ] && config_score=$((config_score + 2))
  [ -d "$project_dir/memory-vault" ] && config_score=$((config_score + 3))
  [ -f "$project_dir/.gitignore" ] && config_score=$((config_score + 2))

  [ -f "$project_dir/Dockerfile" ] && infra_score=$((infra_score + 3))
  [ -d "$project_dir/.github/workflows" ] && infra_score=$((infra_score + 4))

  echo "{\"Testing\":$test_score,\"Security\":$sec_score,\"Documentation\":$doc_score,\"Configuration\":$config_score,\"Quality\":$quality_score,\"Infrastructure\":$infra_score}"
}

extract_agent_data() {
  local project_dir="$1"

  if [ ! -d "$project_dir/.tasuki/agents" ]; then
    echo '[]'
    return
  fi

  echo "["
  local first=true
  for f in "$project_dir/.tasuki/agents"/*.md; do
    [ -f "$f" ] || continue
    local name
    name=$(basename "$f" .md)
    [ "$name" = "onboard" ] && continue
    local model
    model=$(grep "^model:" "$f" 2>/dev/null | head -1 | sed 's/model:\s*//')
    local domains
    domains=$(grep "^domains:" "$f" 2>/dev/null | head -1 | sed 's/domains:\s*//' | sed 's/\[//;s/\]//')

    $first || echo ","
    first=false
    echo "{\"name\":\"$name\",\"model\":\"$model\",\"domains\":\"$domains\"}"
  done
  echo "]"
}

serve_dashboard() {
  local project_dir="${1:-.}"
  project_dir="$(cd "$project_dir" && pwd)"
  local output="$project_dir/.tasuki/dashboard.html"
  local port=8686

  generate_dashboard "$project_dir"

  # Kill any existing dashboard server on this port
  fuser -k "$port/tcp" 2>/dev/null
  sleep 0.5

  if ! command -v python3 &>/dev/null; then
    log_error "python3 required to serve dashboard"
    log_info "Open manually: $output"
    exit 1
  fi

  echo ""
  echo -e "${BOLD}Tasuki Dashboard${NC}"
  echo -e "  ${GREEN}→${NC} http://localhost:$port/dashboard.html"
  echo -e "  ${DIM}Live — auto-updates when pipeline state changes${NC}"
  echo -e "  ${DIM}Press Ctrl+C to stop${NC}"
  echo ""

  cd "$(dirname "$output")"
  TASUKI_ROOT="$TASUKI_ROOT" python3 - "$project_dir" << 'PYEOF' &
import http.server, socketserver, subprocess, os, sys, time, threading, json

PROJECT_DIR = sys.argv[1] if len(sys.argv) > 1 else "."
TASUKI_ROOT = os.environ.get("TASUKI_ROOT", "")
DASHBOARD_SCRIPT = os.path.join(TASUKI_ROOT, "src/engine/dashboard.sh") if TASUKI_ROOT else ""

# Files to watch for changes
WATCH_FILES = [
    os.path.join(PROJECT_DIR, ".tasuki/config/pipeline-progress.json"),
    os.path.join(PROJECT_DIR, ".tasuki/config/activity-log.json"),
    os.path.join(PROJECT_DIR, ".tasuki/config/pipeline-history.log"),
]

generation = 0  # increments on every regeneration
last_mtimes = {}

def get_mtimes():
    mtimes = {}
    for f in WATCH_FILES:
        try:
            mtimes[f] = os.path.getmtime(f)
        except OSError:
            mtimes[f] = 0
    return mtimes

def regenerate():
    global generation
    if DASHBOARD_SCRIPT and os.path.exists(DASHBOARD_SCRIPT):
        subprocess.run(["bash", DASHBOARD_SCRIPT, PROJECT_DIR],
                       capture_output=True, env={**os.environ, "TASUKI_GENERATE_ONLY": "1"})
    generation += 1

def watcher():
    global last_mtimes
    last_mtimes = get_mtimes()
    while True:
        time.sleep(2)
        current = get_mtimes()
        if current != last_mtimes:
            last_mtimes = current
            regenerate()

threading.Thread(target=watcher, daemon=True).start()

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/events":
            # SSE endpoint — browser listens for reload signals
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            last_seen = generation
            try:
                while True:
                    if generation != last_seen:
                        last_seen = generation
                        self.wfile.write(f"data: reload\n\n".encode())
                        self.wfile.flush()
                    time.sleep(1)
            except (BrokenPipeError, ConnectionResetError):
                pass
        elif self.path == "/refresh":
            regenerate()
            self.send_response(302)
            self.send_header("Location", "/dashboard.html")
            self.end_headers()
        else:
            super().do_GET()

    def log_message(self, format, *args):
        pass

class ThreadedServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True

with ThreadedServer(("0.0.0.0", 8686), Handler) as httpd:
    httpd.serve_forever()
PYEOF

  local server_pid=$!

  if command -v xdg-open &>/dev/null; then
    xdg-open "http://localhost:$port/dashboard.html" 2>/dev/null &
  elif command -v open &>/dev/null; then
    open "http://localhost:$port/dashboard.html" 2>/dev/null &
  fi

  trap "kill $server_pid 2>/dev/null; echo ''; log_info 'Dashboard stopped.'; exit 0" INT TERM
  wait $server_pid
}

extract_activity_data() {
  local project_dir="$1"
  local activity_file="$project_dir/.tasuki/config/activity-log.json"

  if [ -f "$activity_file" ]; then
    cat "$activity_file"
  else
    echo '{"events":[]}'
  fi
}

extract_rag_data() {
  local project_dir="$1"
  local rag_file="$project_dir/.tasuki/config/rag-sync-batch.jsonl"

  if [ -f "$rag_file" ] && command -v python3 &>/dev/null; then
    python3 -c "
import json
entries = []
with open('$rag_file') as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try:
            e = json.loads(line)
            entries.append({'type': e.get('type','?'), 'name': e.get('name',''), 'tags': e.get('tags',''), 'id': e.get('id','')})
        except: pass
print(json.dumps({'entries': entries}))
" 2>/dev/null
  else
    echo '{"entries":[]}'
  fi
}

extract_progress_data() {
  local project_dir="$1"
  local progress_file="$project_dir/.tasuki/config/pipeline-progress.json"

  if [ -f "$progress_file" ]; then
    cat "$progress_file"
  else
    echo '{"task":null,"status":"idle","current_stage":0,"total_stages":9,"stages":{}}'
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  export TASUKI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  if [ -n "${TASUKI_GENERATE_ONLY:-}" ]; then
    generate_dashboard "${1:-.}"
  else
    serve_dashboard "${1:-.}"
  fi
fi
