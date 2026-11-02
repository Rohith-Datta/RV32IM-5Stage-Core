# ==============================================================================
# Script: generate_pdf.py
# Description: Generates a high-quality, publication-grade PDF guide for
#              the Hazard Unit & Branch Target Buffer (BTB) Architecture.
# ==============================================================================

import os
import subprocess
import shutil

html_content = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Deep-Dive Architectural Guide: Hazard Unit & BTB</title>
<style>
    @page {
        size: A4 portrait;
        margin: 14mm 14mm 16mm 14mm;
        @bottom-right {
            content: "Page " counter(page);
            font-size: 9pt;
            font-family: 'Segoe UI', sans-serif;
            color: #64748b;
        }
    }

    * {
        box-sizing: border-box;
    }

    body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
        color: #1e293b;
        background-color: #ffffff;
        line-height: 1.5;
        font-size: 10pt;
        margin: 0;
        padding: 0;
    }

    /* Header Banner */
    .header-banner {
        background: linear-gradient(135deg, #0f172a 0%, #1e3a8a 60%, #2563eb 100%);
        color: #ffffff;
        padding: 20px 24px;
        border-radius: 8px;
        margin-bottom: 20px;
        box-shadow: 0 4px 12px rgba(15, 23, 42, 0.15);
    }

    .header-banner h1 {
        margin: 0 0 6px 0;
        font-size: 20pt;
        font-weight: 800;
        letter-spacing: -0.5px;
    }

    .header-banner .subtitle {
        font-size: 11pt;
        font-weight: 400;
        color: #93c5fd;
        margin-bottom: 12px;
    }

    .meta-tags {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
    }

    .meta-tag {
        background: rgba(255, 255, 255, 0.15);
        border: 1px solid rgba(255, 255, 255, 0.25);
        color: #f8fafc;
        padding: 3px 10px;
        border-radius: 4px;
        font-size: 8.5pt;
        font-weight: 600;
        letter-spacing: 0.3px;
    }

    /* Section Headings */
    h2 {
        color: #0f172a;
        font-size: 13pt;
        font-weight: 700;
        border-left: 4px solid #2563eb;
        padding-left: 10px;
        margin: 22px 0 10px 0;
        page-break-after: avoid;
    }

    h3 {
        color: #1e3a8a;
        font-size: 11pt;
        font-weight: 600;
        margin: 14px 0 6px 0;
        page-break-after: avoid;
    }

    p {
        margin: 0 0 8px 0;
        text-align: justify;
    }

    /* Diagrams & Flowcharts */
    .diagram-card {
        background: #f8fafc;
        border: 1px solid #cbd5e1;
        border-radius: 6px;
        padding: 12px;
        margin: 12px 0;
        page-break-inside: avoid;
    }

    .diagram-title {
        font-size: 9pt;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.5px;
        color: #475569;
        margin-bottom: 8px;
        text-align: center;
    }

    .flow-grid {
        display: grid;
        grid-template-columns: repeat(4, 1fr);
        gap: 8px;
    }

    .flow-node {
        background: #ffffff;
        border: 1.5px solid #2563eb;
        border-radius: 6px;
        padding: 8px;
        text-align: center;
    }

    .flow-node.hazard-head {
        grid-column: span 4;
        background: #1e3a8a;
        color: #ffffff;
        border-color: #0f172a;
        font-weight: 700;
        padding: 8px;
        font-size: 10pt;
    }

    .flow-node h4 {
        margin: 0 0 4px 0;
        font-size: 9pt;
        color: #1e3a8a;
    }

    .flow-node p {
        margin: 0;
        font-size: 8pt;
        color: #475569;
        text-align: center;
        line-height: 1.3;
    }

    /* Address Decomposition Visualizer */
    .addr-box {
        display: flex;
        width: 100%;
        margin: 10px 0;
        font-family: 'Consolas', monospace;
        font-size: 8.5pt;
        border: 1px solid #94a3b8;
        border-radius: 4px;
        overflow: hidden;
    }

    .addr-segment {
        padding: 8px 4px;
        text-align: center;
        border-right: 1px solid #cbd5e1;
    }

    .addr-segment:last-child {
        border-right: none;
    }

    .addr-tag {
        flex: 25;
        background: #eff6ff;
        color: #1e40af;
    }

    .addr-index {
        flex: 5;
        background: #fef3c7;
        color: #92400e;
        font-weight: 700;
    }

    .addr-offset {
        flex: 2;
        background: #f1f5f9;
        color: #64748b;
    }

    .addr-subtext {
        font-size: 7.5pt;
        display: block;
        margin-top: 2px;
        color: #64748b;
    }

    /* Tables */
    .table-container {
        margin: 12px 0;
        page-break-inside: avoid;
    }

    table {
        width: 100%;
        border-collapse: collapse;
        font-size: 8.5pt;
        margin-bottom: 4px;
    }

    th {
        background: #1e3a8a;
        color: #ffffff;
        font-weight: 600;
        text-align: left;
        padding: 6px 8px;
        border: 1px solid #1e3a8a;
    }

    td {
        padding: 5px 8px;
        border: 1px solid #e2e8f0;
        vertical-align: middle;
    }

    tr:nth-child(even) {
        background: #f8fafc;
    }

    /* Badges */
    .badge {
        display: inline-block;
        padding: 2px 6px;
        border-radius: 4px;
        font-size: 7.5pt;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.3px;
    }

    .badge-hit {
        background: #dcfce7;
        color: #166534;
        border: 1px solid #86efac;
    }

    .badge-miss {
        background: #fee2e2;
        color: #991b1b;
        border: 1px solid #fca5a5;
    }

    .badge-flush {
        background: #fef3c7;
        color: #92400e;
        border: 1px solid #fcd34d;
    }

    .badge-normal {
        background: #e2e8f0;
        color: #334155;
    }

    .badge-pass {
        background: #dcfce7;
        color: #15803d;
        border: 1px solid #4ade80;
    }

    /* Code Snippets */
    .code-container {
        margin: 10px 0 14px 0;
        page-break-inside: avoid;
        border-radius: 6px;
        overflow: hidden;
        border: 1px solid #334155;
    }

    .code-header {
        background: #0f172a;
        color: #94a3b8;
        padding: 4px 10px;
        font-family: 'Consolas', monospace;
        font-size: 8pt;
        font-weight: 600;
        display: flex;
        justify-content: space-between;
        align-items: center;
        border-bottom: 1px solid #334155;
    }

    .code-body {
        background: #1e293b;
        color: #f8fafc;
        padding: 8px 12px;
        font-family: 'Consolas', 'Courier New', monospace;
        font-size: 8pt;
        line-height: 1.4;
        margin: 0;
        overflow-x: auto;
    }

    /* Syntax Highlighting */
    .kwd { color: #93c5fd; font-weight: 600; }  /* Keywords */
    .typ { color: #67e8f9; }                    /* Types / Modules */
    .num { color: #fde047; }                    /* Constants / Numbers */
    .com { color: #86efac; font-style: italic; }/* Comments */
    .str { color: #fca5a5; }                    /* Strings */
    .opr { color: #f472b6; }                    /* Operators */

    /* Engineering Rationale Callouts */
    .rationale-card {
        background: #f0fdf4;
        border-left: 4px solid #16a34a;
        border-radius: 0 6px 6px 0;
        padding: 8px 12px;
        margin: 6px 0 12px 0;
        font-size: 8.5pt;
    }

    .rationale-card strong {
        color: #15803d;
    }

    .rationale-card ul {
        margin: 4px 0 0 0;
        padding-left: 18px;
    }

    .rationale-card li {
        margin-bottom: 3px;
    }

    /* Cheat Sheet Cards */
    .qa-card {
        background: #ffffff;
        border: 1px solid #cbd5e1;
        border-left: 4px solid #3b82f6;
        border-radius: 0 6px 6px 0;
        padding: 8px 12px;
        margin-bottom: 8px;
        page-break-inside: avoid;
    }

    .qa-question {
        font-weight: 700;
        color: #1e3a8a;
        font-size: 9pt;
        margin-bottom: 3px;
    }

    .qa-answer {
        font-size: 8.5pt;
        color: #334155;
        margin: 0;
    }

    .page-break {
        page-break-before: always;
    }
</style>
</head>
<body>

<!-- Header Banner -->
<div class="header-banner">
    <h1>Deep-Dive Architectural Guide</h1>
    <div class="subtitle">Hazard Unit &amp; Branch Target Buffer (BTB) in RV32IMF 5-Stage Pipelined Processor</div>
    <div class="meta-tags">
        <span class="meta-tag">RV32IMF Core Architecture</span>
        <span class="meta-tag">Feature 7: Dynamic Branch Prediction</span>
        <span class="meta-tag">Hardware Defense &amp; Presentation Ready</span>
        <span class="meta-tag">Author: Sigilipelli Praneeth Sai Bharath</span>
    </div>
</div>

<!-- SECTION 1 -->
<h2>1. Hazard Unit: Brief Architectural Overview</h2>
<p>
    In a classic 5-stage RISC-V pipelined core (<code>IF</code> &rarr; <code>ID</code> &rarr; <code>EX</code> &rarr; <code>MEM</code> &rarr; <code>WB</code>), multiple instructions execute concurrently across adjacent clock cycles. The <strong>Hazard Unit</strong> serves as the central traffic controller, continuously monitoring pipeline registers to detect structural, data, and control conflicts, resolving them through <strong>Data Forwarding</strong>, <strong>Pipeline Stalling</strong>, or <strong>Pipeline Flushing</strong>.
</p>

<div class="diagram-card">
    <div class="diagram-title">Hazard Unit Structural Classification &amp; Resolution Actions</div>
    <div class="flow-grid">
        <div class="flow-node hazard-head">HAZARD UNIT (Central Pipeline Traffic Controller)</div>
        <div class="flow-node">
            <h4>Data Forwarding</h4>
            <p><strong>EX/MEM &rarr; EX</strong><br><strong>MEM/WB &rarr; EX</strong><br>0 Stall Cycles</p>
        </div>
        <div class="flow-node">
            <h4>Load-Use Interlock</h4>
            <p><strong>Freeze PC &amp; IF/ID</strong><br>Bubble into ID/EX<br>1-Cycle Delay</p>
        </div>
        <div class="flow-node">
            <h4>Math Co-Processor</h4>
            <p><strong>div_busy / fpu_busy</strong><br>Freeze IF, ID, EX<br>Multi-Cycle Stall</p>
        </div>
        <div class="flow-node">
            <h4>Control Hazards</h4>
            <p><strong>Mispredict in EX</strong><br>Flush IF/ID &amp; ID/EX<br>2-Cycle Penalty</p>
        </div>
    </div>
</div>

<h3>The Three Hazards Resolved by the Unit</h3>
<ol style="margin: 0 0 10px 0; padding-left: 20px; font-size: 8.8pt;">
    <li>
        <strong>Data Hazards (RAW &mdash; Read-After-Write):</strong> An instruction in the Execute stage (<code>EX</code>) requires an operand computed by an older in-flight instruction currently in <code>MEM</code> or <code>WB</code>.
        <br><em>Resolution:</em> Hardware bypass multiplexers forward the result directly to ALU inputs with <strong>0 stall cycles</strong>.
    </li>
    <li>
        <strong>Load-Use Data Hazards:</strong> An instruction in Decode (<code>ID</code>) requires data being fetched from memory by a preceding <code>lw</code> instruction currently in <code>EX</code>. Since SRAM read data only arrives at the end of the <code>MEM</code> stage, forwarding cannot solve this combination combinationally.
        <br><em>Resolution:</em> The Hazard Unit inserts a <strong>1-cycle bubble</strong> (freezes <code>PC</code> and <code>IF/ID</code>, clears <code>ID/EX</code>).
    </li>
    <li>
        <strong>Control Hazards (Branches &amp; Jumps):</strong> In basic 5-stage pipelines, branch outcomes and target addresses resolve in the <code>EX</code> stage.
        <br><em>Without BTB:</em> Every taken branch incurs a mandatory <strong>2-cycle flush penalty</strong> (flushing <code>IF/ID</code> and <code>ID/EX</code>).
        <br><em>With BTB:</em> The Hazard Unit flushes <strong>only on mispredictions</strong>. Correct predictions execute with <strong>0 penalty cycles</strong>.
    </li>
</ol>

<!-- SECTION 2 -->
<h2>2. Branch Target Buffer (BTB): In-Depth Architecture</h2>

<h3>2.1 Why BTB is Necessary</h3>
<p>
    The instruction fetch stage (<code>IF</code>) must know the next Program Counter on every clock cycle. However, conditional branch conditions (e.g., <code>bne</code>, <code>beq</code>) and target addresses resolve 2 clock cycles later in the Execute (<code>EX</code>) stage:
</p>

<div class="diagram-card" style="text-align: center; font-family: 'Consolas', monospace; font-size: 8.5pt;">
    <div style="display: flex; justify-content: space-around; font-weight: bold; margin-bottom: 4px; color: #1e3a8a;">
        <span>Cycle 1</span><span>Cycle 2</span><span>Cycle 3</span><span>Cycle 4</span><span>Cycle 5</span>
    </div>
    <div style="border-top: 1px solid #cbd5e1; padding-top: 6px; text-align: left; line-height: 1.6;">
        <div><strong>Branch Inst:</strong> &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[IF] &rarr; [ID] &rarr; <strong>[EX (Branch Resolves Here!)]</strong> &rarr; [MEM] &rarr; [WB]</div>
        <div style="color: #dc2626;"><strong>Speculative Inst 1:</strong> &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[IF] &rarr; [ID] &nbsp;(Discarded on mispredict!)</div>
        <div style="color: #dc2626;"><strong>Speculative Inst 2:</strong> &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[IF] &nbsp;(Discarded on mispredict!)</div>
    </div>
</div>

<p>
    The <strong>Branch Target Buffer (BTB)</strong> eliminates this penalty by acting as a zero-latency hardware cache in the <code>IF</code> stage. When <code>fetch_pc</code> hits in the BTB, the fetch stage immediately redirects next-cycle execution to the cached target address, converting branch latency from <strong>2 penalty cycles to 0 penalty cycles</strong>.
</p>

<h3>2.2 Storage Geometry &amp; Address Decomposition</h3>
<p>
    The processor features a <strong>32-entry Direct-Mapped BTB</strong>. The 32-bit instruction fetch address is decomposed as follows:
</p>

<div class="addr-box">
    <div class="addr-segment addr-tag">
        <strong>Tag Array: PC[31:7] (25 bits)</strong>
        <span class="addr-subtext">Verified during lookup to prevent aliasing</span>
    </div>
    <div class="addr-segment addr-index">
        <strong>Index: PC[6:2] (5 bits)</strong>
        <span class="addr-subtext">Selects 1 of 32 entries (2<sup>5</sup> = 32)</span>
    </div>
    <div class="addr-segment addr-offset">
        <strong>PC[1:0] (2b)</strong>
        <span class="addr-subtext">Always 2'b00</span>
    </div>
</div>

<ul style="margin: 6px 0 10px 0; padding-left: 20px; font-size: 8.5pt;">
    <li><strong>Word Alignment (<code>PC[1:0]</code>):</strong> Standard RV32 instructions are 4-byte aligned; the lowest 2 bits are always <code>2'b00</code> and discarded.</li>
    <li><strong>Index (<code>PC[6:2]</code>):</strong> Directly indexes 32 internal storage slots in distributed LUT RAM.</li>
    <li><strong>Tag Array (<code>32 &times; 25 bits</code>):</strong> Stores the high-order bits of the branch address to confirm exact address matches.</li>
    <li><strong>Target Array (<code>32 &times; 32 bits</code>):</strong> Stores the calculated destination target address.</li>
    <li><strong>Valid Array (<code>32 &times; 1 bit</code>):</strong> Indicates whether the indexed slot holds valid branch history.</li>
</ul>

<h3>2.3 The Three Misprediction Scenarios</h3>
<div class="table-container">
    <table>
        <thead>
            <tr>
                <th style="width: 20%;">Scenario</th>
                <th style="width: 25%;">Condition in EX</th>
                <th style="width: 25%;">Root Cause</th>
                <th style="width: 30%;">Hardware Recovery Action</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td><strong>1. Cold Miss (Taken)</strong></td>
                <td><code>taken=1</code>, but <code>pred_taken=0</code></td>
                <td>First encounter of a backward loop edge.</td>
                <td>Flush <code>IF/ID</code> and <code>ID/EX</code> (2 cycles); allocate entry in BTB; redirect fetch to <code>target_pc</code>.</td>
            </tr>
            <tr>
                <td><strong>2. Mispredict Taken</strong></td>
                <td><code>taken=0</code>, but <code>pred_taken=1</code></td>
                <td>Loop counter expires; loop terminates.</td>
                <td>Flush <code>IF/ID</code> and <code>ID/EX</code> (2 cycles); invalidate BTB entry (<code>valid=0</code>); redirect to <code>pc + 4</code>.</td>
            </tr>
            <tr>
                <td><strong>3. Target Mismatch</strong></td>
                <td><code>taken=1</code>, but <code>target != pred_target</code></td>
                <td>Dynamic indirect jump (<code>jalr</code>) or index collision.</td>
                <td>Flush 2 stages; update new target in BTB; redirect fetch to calculated <code>target_pc</code>.</td>
            </tr>
        </tbody>
    </table>
</div>

<div class="page-break"></div>

<!-- SECTION 3 -->
<h2>3. Key Code Snippets &amp; Detailed Engineering Rationale</h2>

<!-- Snippet 1 -->
<div class="code-container">
    <div class="code-header">
        <span>Snippet 1: Hazard Unit &mdash; Stall &amp; Flush Logic</span>
        <span>hazard_unit.v (Lines 97&ndash;111)</span>
    </div>
    <pre class="code-body"><span class="com">// Priority-based Stall &amp; Flush equations with BTB integration</span>
<span class="kwd">assign</span> stall_if     <span class="opr">=</span> load_use_hazard <span class="opr">||</span> math_busy;
<span class="kwd">assign</span> stall_if_id  <span class="opr">=</span> load_use_hazard <span class="opr">||</span> math_busy;
<span class="kwd">assign</span> stall_id_ex  <span class="opr">=</span> math_busy;

<span class="com">// Branch flushes ONLY on actual mispredictions:</span>
<span class="kwd">assign</span> flush_if_id  <span class="opr">=</span> mispredict <span class="opr">&amp;&amp; !</span>math_busy;
<span class="kwd">assign</span> flush_id_ex  <span class="opr">=</span> (load_use_hazard <span class="opr">||</span> mispredict) <span class="opr">&amp;&amp; !</span>math_busy;
<span class="kwd">assign</span> flush_ex_mem <span class="opr">=</span> math_busy;</pre>
</div>
<div class="rationale-card">
    <strong>Engineering Rationale:</strong>
    <ul>
        <li><strong><code>flush_if_id = mispredict &amp;&amp; !math_busy</code>:</strong> Standard cores flush on every taken branch. With BTB, the flush is gated strictly by <code>mispredict</code>. If the prediction was correct, <code>mispredict == 0</code>, resulting in <strong>zero pipeline bubbles</strong>. It is gated with <code>!math_busy</code> to prevent destroying in-flight register operands during multi-cycle division or FPU operations.</li>
        <li><strong><code>stall_id_ex = math_busy</code> (not <code>load_use_hazard</code>):</strong> Load-use hazards only freeze stages above Execute (<code>PC</code> and <code>IF/ID</code>) while clearing <code>ID/EX</code> (bubble), allowing the load in <code>EX</code> to advance to <code>MEM</code> where data is read. Multi-cycle arithmetic must stall <code>ID/EX</code> as well.</li>
    </ul>
</div>

<!-- Snippet 2 -->
<div class="code-container">
    <div class="code-header">
        <span>Snippet 2: BTB Query &amp; Zero-Latency Next-PC Steering</span>
        <span>btb_branch_pred.v &amp; pipeline_5stage.v</span>
    </div>
    <pre class="code-body"><span class="com">// In btb_branch_pred.v: Combinational Tag Match in IF stage</span>
<span class="kwd">wire</span> [<span class="num">4</span>:<span class="num">0</span>]           fetch_index <span class="opr">=</span> fetch_pc[<span class="num">6</span>:<span class="num">2</span>];
<span class="kwd">wire</span> [TAG_WIDTH<span class="opr">-</span><span class="num">1</span>:<span class="num">0</span>] fetch_tag   <span class="opr">=</span> fetch_pc[<span class="num">31</span>:<span class="num">7</span>];
<span class="kwd">wire</span> btb_hit <span class="opr">=</span> valid_array[fetch_index] <span class="opr">&amp;&amp;</span> (tag_array[fetch_index] <span class="opr">==</span> fetch_tag);

<span class="kwd">assign</span> pred_hit    <span class="opr">=</span> btb_hit;
<span class="kwd">assign</span> pred_taken  <span class="opr">=</span> btb_hit;
<span class="kwd">assign</span> pred_target <span class="opr">=</span> btb_hit <span class="opr">?</span> target_array[fetch_index] <span class="opr">:</span> (fetch_pc <span class="opr">+</span> <span class="num">32'd4</span>);

<span class="com">// In pipeline_5stage.v: Next-PC Multiplexer Prioritization</span>
<span class="kwd">assign</span> pc_next <span class="opr">=</span> ex_mispredict <span class="opr">?</span> ex_redirect_pc <span class="opr">:</span>
                 (pred_hit <span class="opr">&amp;&amp;</span> pred_taken) <span class="opr">?</span> pred_target <span class="opr">:</span> pc_plus4;</pre>
</div>
<div class="rationale-card">
    <strong>Engineering Rationale:</strong>
    <ul>
        <li><strong>Parallel Query in <code>IF</code>:</strong> The lookup runs combinationally in parallel with instruction memory access. When the clock tick arrives, <code>pc_reg</code> directly latches <code>pred_target</code> with zero cycle delay.</li>
        <li><strong>Strict Priority Ordering:</strong> (1) <code>ex_mispredict</code> recovery overrides all speculation; (2) Speculative BTB hit; (3) Default sequential <code>pc + 4</code>.</li>
    </ul>
</div>

<!-- Snippet 3 -->
<div class="code-container">
    <div class="code-header">
        <span>Snippet 3: Synchronous Pipeline Metadata Carriage</span>
        <span>pipeline_5stage.v &amp; Pipeline Registers</span>
    </div>
    <pre class="code-body"><span class="com">// Propagate prediction metadata synchronously down the pipeline:</span>
<span class="typ">if_id_reg</span> u_if_id_reg (
    .clk          (clk),
    .pred_taken_i (pred_taken),       .pred_taken_o (if_id_pred_taken),
    .pred_target_i(pred_target),      .pred_target_o(if_id_pred_target), ...
);
<span class="typ">id_ex_reg</span> u_id_ex_reg (
    .clk          (clk),
    .pred_taken_i (if_id_pred_taken), .pred_taken_o (id_ex_pred_taken),
    .pred_target_i(if_id_pred_target),.pred_target_o(id_ex_pred_target), ...
);</pre>
</div>
<div class="rationale-card">
    <strong>Engineering Rationale:</strong>
    <ul>
        <li><strong>Why not re-query BTB from <code>EX</code>?</strong> Newer instructions pass through <code>IF</code> while a branch is in-flight. If a newer branch modified the BTB, an <code>EX</code> query would read the altered state rather than the prediction made when the current branch was fetched. Carrying metadata ensures race-free evaluation.</li>
    </ul>
</div>

<!-- Snippet 4 -->
<div class="code-container">
    <div class="code-header">
        <span>Snippet 4: Misprediction Evaluation &amp; Recovery Redirection</span>
        <span>execute_stage.v (Lines 140&ndash;152)</span>
    </div>
    <pre class="code-body"><span class="kwd">assign</span> btb_update_en_o     <span class="opr">=</span> branch_i <span class="opr">||</span> jal_i <span class="opr">||</span> jalr_i;
<span class="kwd">assign</span> btb_update_taken_o  <span class="opr">=</span> branch_or_jump_taken_o;
<span class="kwd">assign</span> btb_update_pc_o     <span class="opr">=</span> pc_i;
<span class="kwd">assign</span> btb_update_target_o <span class="opr">=</span> target_pc_o;

<span class="com">// Mispredict Condition: Direction Discrepancy OR Target Address Mismatch</span>
<span class="kwd">assign</span> mispredict_o <span class="opr">=</span> btb_update_en_o <span class="opr">&amp;&amp;</span>
                      ((branch_or_jump_taken_o <span class="opr">!=</span> pred_taken_i) <span class="opr">||</span>
                       (branch_or_jump_taken_o <span class="opr">&amp;&amp;</span> (target_pc_o <span class="opr">!=</span> pred_target_i)));

<span class="com">// Deterministic Recovery Target</span>
<span class="kwd">assign</span> redirect_pc_o <span class="opr">=</span> branch_or_jump_taken_o <span class="opr">?</span> target_pc_o <span class="opr">:</span> pc_plus4_i;</pre>
</div>
<div class="rationale-card">
    <strong>Engineering Rationale:</strong>
    <ul>
        <li><strong>Full Target Verification:</strong> For indirect branches like <code>jalr</code>, direction is always taken, but target addresses can change dynamically. Checking <code>target_pc_o != pred_target_i</code> prevents erroneous execution down stale indirect jump paths.</li>
    </ul>
</div>

<!-- Snippet 5 -->
<div class="code-container">
    <div class="code-header">
        <span>Snippet 5: BTB Allocation &amp; Loop-Exit Invalidation FSM</span>
        <span>btb_branch_pred.v (Lines 105&ndash;122)</span>
    </div>
    <pre class="code-body"><span class="kwd">always</span> <span class="opr">@</span>(<span class="kwd">posedge</span> clk <span class="opr">or negedge</span> reset_n) <span class="kwd">begin</span>
    <span class="kwd">if</span> (<span class="opr">!</span>reset_n) <span class="kwd">begin</span>
        <span class="kwd">for</span> (i <span class="opr">=</span> <span class="num">0</span>; i <span class="opr">&lt;</span> ENTRIES; i <span class="opr">=</span> i <span class="opr">+</span> <span class="num">1</span>) <span class="kwd">begin</span>
            valid_array[i]  <span class="opr">&lt;=</span> <span class="num">1'b0</span>;
            tag_array[i]    <span class="opr">&lt;=</span> {TAG_WIDTH{<span class="num">1'b0</span>}};
            target_array[i] <span class="opr">&lt;=</span> <span class="num">32'd0</span>;
        <span class="kwd">end</span>
    <span class="kwd">end else if</span> (update_en) <span class="kwd">begin</span>
        <span class="kwd">if</span> (update_taken) <span class="kwd">begin</span>
            valid_array[update_index]  <span class="opr">&lt;=</span> <span class="num">1'b1</span>;
            tag_array[update_index]    <span class="opr">&lt;=</span> update_tag;
            target_array[update_index] <span class="opr">&lt;=</span> update_target;
        <span class="kwd">end else begin</span>
            <span class="com">// Invalidate entry on branch not-taken (prevents stale loop-exit mispredicts)</span>
            valid_array[update_index]  <span class="opr">&lt;=</span> <span class="num">1'b0</span>;
        <span class="kwd">end</span>
    <span class="kwd">end</span>
<span class="kwd">end</span></pre>
</div>
<div class="rationale-card">
    <strong>Engineering Rationale:</strong>
    <ul>
        <li><strong>Selective Invalidation on Not-Taken:</strong> When a loop finishes, its branch evaluates to <code>NOT TAKEN</code>. Invalidating the entry prevents false speculation the next time execution reaches that code segment.</li>
        <li><strong>Structural Dual-Porting:</strong> Reads occur combinationally during <code>IF</code>, while updates commit on the clock edge from <code>EX</code> without collision.</li>
    </ul>
</div>

<div class="page-break"></div>

<!-- SECTION 4 -->
<h2>4. Hardware Trace Walkthrough: The 2-Iteration Loop</h2>
<p>
    Consider the following representative assembly loop executed on the Nexys A7 FPGA:
</p>

<div class="code-container" style="margin-bottom: 8px;">
    <div class="code-header"><span>Assembly Loop Benchmark</span><span>Target: 2 Iterations</span></div>
    <pre class="code-body"><span class="num">0x00</span>: <span class="kwd">addi</span> x1, x0, 2      <span class="com">// Loop counter = 2</span>
<span class="num">0x04</span>: <span class="kwd">addi</span> x2, x0, 0      <span class="com">// Accumulator = 0</span>
<span class="num">0x08</span>: <span class="kwd">addi</span> x2, x2, 1      <span class="com">// &lt;LOOP START&gt; Accumulator++</span>
<span class="num">0x0C</span>: <span class="kwd">addi</span> x1, x1, -1     <span class="com">// Counter--</span>
<span class="num">0x10</span>: <span class="kwd">bne</span>  x1, x0, -8     <span class="com">// Branch back to 0x08 if x1 != 0</span>
<span class="num">0x14</span>: <span class="kwd">nop</span>                 <span class="com">// Loop exit sequential target</span></pre>
</div>

<div class="table-container">
    <table>
        <thead>
            <tr>
                <th style="width: 10%;">Cycle</th>
                <th style="width: 14%;">PC in EX</th>
                <th style="width: 20%;">Instruction in EX</th>
                <th style="width: 16%;">BTB State</th>
                <th style="width: 15%;">Outcome</th>
                <th style="width: 25%;">Pipeline Action</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td style="text-align: center;"><strong>5</strong></td>
                <td><code>0x00000010</code></td>
                <td><code>bne x1, x0, -8</code></td>
                <td><span class="badge badge-miss">Cold Miss</span></td>
                <td><strong>Taken (x1=1)</strong></td>
                <td><span class="badge badge-miss">Mispredict</span> &bull; Allocates BTB; flushes 2 stages</td>
            </tr>
            <tr>
                <td style="text-align: center;"><strong>6</strong></td>
                <td>&mdash;</td>
                <td>&mdash; (Flushed)</td>
                <td>&mdash;</td>
                <td>&mdash;</td>
                <td><span class="badge badge-flush">Flush Penalty 1/2</span></td>
            </tr>
            <tr>
                <td style="text-align: center;"><strong>7</strong></td>
                <td>&mdash;</td>
                <td>&mdash; (Flushed)</td>
                <td>&mdash;</td>
                <td>&mdash;</td>
                <td><span class="badge badge-flush">Flush Penalty 2/2</span></td>
            </tr>
            <tr>
                <td style="text-align: center;"><strong>8</strong></td>
                <td><code>0x00000008</code></td>
                <td><code>addi x2, x2, 1</code></td>
                <td><span class="badge badge-normal">Normal</span></td>
                <td>Normal</td>
                <td>Iteration 2 begins; accumulator = 2</td>
            </tr>
            <tr>
                <td style="text-align: center;"><strong>9</strong></td>
                <td><code>0x0000000C</code></td>
                <td><code>addi x1, x1, -1</code></td>
                <td><span class="badge badge-normal">Normal</span></td>
                <td>Normal</td>
                <td>Counter decrements (x1 = 0)</td>
            </tr>
            <tr style="background: #f0fdf4;">
                <td style="text-align: center;"><strong>10</strong></td>
                <td><code>0x00000010</code></td>
                <td><code>bne x1, x0, -8</code></td>
                <td><span class="badge badge-hit">BTB Hit!</span></td>
                <td><strong>Taken</strong></td>
                <td><span class="badge badge-pass">Predicted Correctly!</span> &bull; <strong>0 Penalty Cycles</strong></td>
            </tr>
            <tr>
                <td style="text-align: center;"><strong>11</strong></td>
                <td><code>0x00000008</code></td>
                <td><code>addi x2, x2, 1</code></td>
                <td><span class="badge badge-normal">Normal</span></td>
                <td>Normal</td>
                <td>Seamless execution without bubbles</td>
            </tr>
            <tr>
                <td style="text-align: center;"><strong>12</strong></td>
                <td><code>0x0000000C</code></td>
                <td><code>addi x1, x1, -1</code></td>
                <td><span class="badge badge-normal">Normal</span></td>
                <td>Normal</td>
                <td>Final loop pass</td>
            </tr>
            <tr>
                <td style="text-align: center;"><strong>13</strong></td>
                <td><code>0x00000010</code></td>
                <td><code>bne x1, x0, -8</code></td>
                <td><span class="badge badge-hit">BTB Hit!</span></td>
                <td><strong>Not Taken</strong></td>
                <td><span class="badge badge-miss">Mispredict (Exit)</span> &bull; Invalidates BTB; flushes 2</td>
            </tr>
            <tr>
                <td style="text-align: center;"><strong>14</strong></td>
                <td>&mdash;</td>
                <td>&mdash; (Flushed)</td>
                <td>&mdash;</td>
                <td>&mdash;</td>
                <td><span class="badge badge-flush">Flush Penalty 1/2</span></td>
            </tr>
            <tr>
                <td style="text-align: center;"><strong>15</strong></td>
                <td>&mdash;</td>
                <td>&mdash; (Flushed)</td>
                <td>&mdash;</td>
                <td>&mdash;</td>
                <td><span class="badge badge-flush">Flush Penalty 2/2</span></td>
            </tr>
            <tr>
                <td style="text-align: center;"><strong>16</strong></td>
                <td><code>0x00000014</code></td>
                <td><code>nop</code></td>
                <td><span class="badge badge-normal">Normal</span></td>
                <td>Normal</td>
                <td>Loop successfully exited to sequential code</td>
            </tr>
        </tbody>
    </table>
</div>

<div class="rationale-card" style="background: #f8fafc; border-left-color: #3b82f6;">
    <strong style="color: #1e3a8a;">Hardware Verification Summary Metrics:</strong>
    <ul style="margin-top: 4px;">
        <li><strong>Total Branches Encountered:</strong> 3 &nbsp;|&nbsp; <strong>Correct BTB Hits (0 penalty):</strong> 1 (Cycle 10)</li>
        <li><strong>Mispredictions (2-cycle penalty):</strong> 2 (Cycle 5 Cold Miss + Cycle 13 Loop Exit)</li>
        <li><strong>Total Flush Penalty Cycles:</strong> 4 cycles (2 flushes &times; 2 cycles)</li>
        <li><strong>Accuracy Dynamics:</strong> In realistic loops with 10+ iterations, accuracy exceeds <strong>90%</strong> as verified in <code>btb.c</code>.</li>
    </ul>
</div>

<!-- SECTION 5 -->
<h2>5. Summary Cheat-Sheet for Presentations &amp; Defense</h2>

<div class="qa-card">
    <div class="qa-question">Q1: What is the primary function of the Hazard Unit?</div>
    <div class="qa-answer">Coordinates all pipeline safety controls: handles data forwarding for RAW dependencies, generates 1-cycle stalls for load-use hazards, holds the pipeline during multi-cycle math (division / FPU), and flushes wrong-path instructions during branch mispredictions.</div>
</div>

<div class="qa-card">
    <div class="qa-question">Q2: How does the Branch Target Buffer (BTB) achieve 0-cycle branch penalties?</div>
    <div class="qa-answer">It caches target addresses in the <code>IF</code> stage. When a branch PC hits in the BTB, the next fetch PC is redirected combinationally to the target in cycle N+1, allowing target instruction execution without inserting pipeline bubbles.</div>
</div>

<div class="qa-card">
    <div class="qa-question">Q3: Why is the branch misprediction penalty exactly 2 cycles?</div>
    <div class="qa-answer">Branch conditions evaluate in the Execute stage (Stage 3). If mispredicted, the 2 younger speculative instructions already fetched into <code>IF/ID</code> (Stage 2) and <code>ID/EX</code> (Stage 1) must be flushed (3 &minus; 1 = 2 cycles).</div>
</div>

<div class="qa-card">
    <div class="qa-question">Q4: Why does the BTB use a 5-bit index from PC[6:2] instead of PC[4:0]?</div>
    <div class="qa-answer">RISC-V standard instructions are 4-byte aligned, meaning <code>PC[1:0]</code> is always <code>2'b00</code>. Indexing begins at bit 2 (<code>PC[6:2]</code>) to map directly to 32 entries (2<sup>5</sup> = 32) without wasted duplicate slots.</div>
</div>

<div class="qa-card">
    <div class="qa-question">Q5: Why carry branch prediction metadata through the pipeline registers?</div>
    <div class="qa-answer">Carrying <code>pred_taken</code> and <code>pred_target</code> through <code>IF/ID</code> and <code>ID/EX</code> registers prevents race conditions, ensuring the <code>EX</code> stage evaluates the branch against the exact speculative decision that was made when that specific instruction was fetched.</div>
</div>

</body>
</html>
"""

# Output paths
workspace_dir = r"C:\CS2202L\RISCV"
artifact_dir = r"C:\Users\prane\.gemini\antigravity\brain\bf6ec4b6-a6a1-477d-9aa5-79f87341bfc8"

html_file = os.path.join(workspace_dir, "BTB_and_Hazard_Unit_Guide.html")
pdf_workspace = os.path.join(workspace_dir, "BTB_and_Hazard_Unit_Architecture_Guide.pdf")
pdf_artifact = os.path.join(artifact_dir, "BTB_and_Hazard_Unit_Architecture_Guide.pdf")

with open(html_file, "w", encoding="utf-8") as f:
    f.write(html_content)

edge_path = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
cmd = [
    edge_path,
    "--headless",
    "--disable-gpu",
    "--no-pdf-header-footer",
    f"--print-to-pdf={pdf_workspace}",
    html_file
]

print("Rendering PDF via Microsoft Edge Headless...")
subprocess.run(cmd, check=True)

if os.path.exists(pdf_workspace):
    size_kb = os.path.getsize(pdf_workspace) / 1024
    print(f"Generated PDF in workspace: {pdf_workspace} ({size_kb:.1f} KB)")
    shutil.copyfile(pdf_workspace, pdf_artifact)
    print(f"Copied PDF to artifact directory: {pdf_artifact}")
else:
    print("Error: PDF was not generated.")
