# ==============================================================================
# Script: build_diagrams.py
# Description: Generates exact, pure black-and-white vector block diagrams
#              for the Hazard Unit and Branch Target Buffer (BTB), then
#              renders a presentation-ready PDF for the project demo.
# ==============================================================================

import os
import subprocess
import shutil

# ==============================================================================
# 1. HAZARD UNIT SVG DEFINITION
# ==============================================================================
svg_hazard_unit = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1150 820" width="100%" height="100%" style="background-color: #ffffff; font-family: Arial, Helvetica, sans-serif;">
  <defs>
    <!-- Arrowhead markers -->
    <marker id="arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 1.5 L 8 5 L 0 8.5 z" fill="#000000" />
    </marker>
    <marker id="dot" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="4" markerHeight="4">
      <circle cx="5" cy="5" r="3" fill="#000000" />
    </marker>
  </defs>

  <!-- Title & Border -->
  <rect x="15" y="15" width="1120" height="790" fill="#ffffff" stroke="#000000" stroke-width="2.5" />
  <text x="575" y="45" font-size="18" font-weight="bold" text-anchor="middle" fill="#000000" letter-spacing="0.5">HAZARD DETECTION &amp; DATA FORWARDING UNIT &mdash; HARDWARE SCHEMATIC</text>
  <text x="575" y="65" font-size="12" font-style="italic" text-anchor="middle" fill="#333333">RV32IMF 5-Stage Pipelined Processor Core (Feature 7 / Feature 9 Architecture)</text>
  <line x1="15" y1="75" x2="1135" y2="75" stroke="#000000" stroke-width="1.5" />

  <!-- ======================================================================== -->
  <!-- SECTION 1: LOAD-USE HAZARD & MATH BUSY DETECTION (TOP LEFT)              -->
  <!-- ======================================================================== -->
  <rect x="35" y="90" width="530" height="340" fill="#ffffff" stroke="#000000" stroke-width="1.5" stroke-dasharray="6,4" />
  <text x="45" y="110" font-size="13" font-weight="bold" fill="#000000">1. LOAD-USE &amp; MULTI-CYCLE MATH INTERLOCK DETECTION</text>

  <!-- Inputs from ID and EX -->
  <text x="45" y="145" font-size="11" font-weight="bold">id_rs1[4:0]</text>
  <line x1="125" y1="140" x2="190" y2="140" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="150" y="135" font-size="10">/5</text>

  <text x="45" y="180" font-size="11" font-weight="bold">id_ex_rd[4:0]</text>
  <line x1="130" y1="175" x2="160" y2="175" stroke="#000000" stroke-width="1.5" />
  <line x1="160" y1="155" x2="190" y2="155" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <line x1="160" y1="215" x2="190" y2="215" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <line x1="160" y1="155" x2="160" y2="270" stroke="#000000" stroke-width="1.5" />
  <circle cx="160" cy="175" r="3" fill="#000000" />
  <circle cx="160" cy="215" r="3" fill="#000000" />
  <text x="140" y="170" font-size="10">/5</text>

  <!-- Comparator 1: id_ex_rd == id_rs1 -->
  <rect x="190" y="130" width="70" height="35" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="225" y="152" font-size="12" font-weight="bold" text-anchor="middle">==</text>
  <text x="225" y="123" font-size="9" text-anchor="middle">5-bit Eq</text>

  <!-- AND1: (id_ex_rd == id_rs1) && id_rs1_used -->
  <line x1="260" y1="148" x2="310" y2="148" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="45" y="210" font-size="11" font-weight="bold">id_rs1_used</text>
  <line x1="125" y1="205" x2="280" y2="205" stroke="#000000" stroke-width="1.5" />
  <line x1="280" y1="205" x2="280" y2="162" stroke="#000000" stroke-width="1.5" />
  <line x1="280" y1="162" x2="310" y2="162" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />

  <path d="M 310,140 L 330,140 A 15,15 0 0,1 330,170 L 310,170 Z" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="325" y="158" font-size="10" font-weight="bold" text-anchor="middle">&amp;</text>

  <!-- Inputs for rs2 -->
  <text x="45" y="245" font-size="11" font-weight="bold">id_rs2[4:0]</text>
  <line x1="125" y1="240" x2="190" y2="240" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="150" y="235" font-size="10">/5</text>

  <!-- Comparator 2: id_ex_rd == id_rs2 -->
  <rect x="190" y="205" width="70" height="35" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="225" y="227" font-size="12" font-weight="bold" text-anchor="middle">==</text>
  <text x="225" y="198" font-size="9" text-anchor="middle">5-bit Eq</text>

  <!-- AND2: (id_ex_rd == id_rs2) && id_rs2_used -->
  <line x1="260" y1="222" x2="310" y2="222" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="45" y="280" font-size="11" font-weight="bold">id_rs2_used</text>
  <line x1="125" y1="275" x2="280" y2="275" stroke="#000000" stroke-width="1.5" />
  <line x1="280" y1="275" x2="280" y2="236" stroke="#000000" stroke-width="1.5" />
  <line x1="280" y1="236" x2="310" y2="236" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />

  <path d="M 310,214 L 330,214 A 15,15 0 0,1 330,244 L 310,244 Z" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="325" y="232" font-size="10" font-weight="bold" text-anchor="middle">&amp;</text>

  <!-- OR Gate: (AND1 || AND2) -->
  <line x1="345" y1="155" x2="370" y2="155" stroke="#000000" stroke-width="1.5" />
  <line x1="370" y1="155" x2="370" y2="185" stroke="#000000" stroke-width="1.5" />
  <line x1="370" y1="185" x2="390" y2="185" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />

  <line x1="345" y1="229" x2="370" y2="229" stroke="#000000" stroke-width="1.5" />
  <line x1="370" y1="229" x2="370" y2="205" stroke="#000000" stroke-width="1.5" />
  <line x1="370" y1="205" x2="390" y2="205" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />

  <path d="M 390,175 Q 402,195 390,215 Q 412,215 425,195 Q 412,175 390,175 Z" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="403" y="198" font-size="9" font-weight="bold">OR</text>

  <!-- Non-zero comparator: id_ex_rd != 0 -->
  <line x1="160" y1="270" x2="190" y2="270" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <rect x="190" y="255" width="70" height="30" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="225" y="274" font-size="11" font-weight="bold" text-anchor="middle">!= 5'd0</text>

  <!-- Final 3-input AND gate for load_use_hazard -->
  <line x1="425" y1="195" x2="470" y2="195" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="45" y="325" font-size="11" font-weight="bold">id_ex_mem_read</text>
  <line x1="150" y1="320" x2="445" y2="320" stroke="#000000" stroke-width="1.5" />
  <line x1="445" y1="320" x2="445" y2="215" stroke="#000000" stroke-width="1.5" />
  <line x1="445" y1="215" x2="470" y2="215" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />

  <line x1="260" y1="270" x2="455" y2="270" stroke="#000000" stroke-width="1.5" />
  <line x1="455" y1="270" x2="455" y2="205" stroke="#000000" stroke-width="1.5" />
  <line x1="455" y1="205" x2="470" y2="205" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />

  <path d="M 470,185 L 490,185 A 20,20 0 0,1 490,225 L 470,225 Z" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="485" y="208" font-size="11" font-weight="bold" text-anchor="middle">&amp;</text>
  <line x1="510" y1="205" x2="550" y2="205" stroke="#000000" stroke-width="2" marker-end="url(#arrow)" />
  <text x="475" y="175" font-size="11" font-weight="bold" fill="#000000">load_use_hazard</text>

  <!-- Multi-cycle math hold (Divider & FPU) -->
  <line x1="35" y1="350" x2="565" y2="350" stroke="#cccccc" stroke-width="1" />
  <text x="45" y="375" font-size="11" font-weight="bold">div_busy</text>
  <line x1="110" y1="370" x2="190" y2="370" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />

  <text x="45" y="410" font-size="11" font-weight="bold">fpu_busy</text>
  <line x1="110" y1="405" x2="190" y2="405" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />

  <path d="M 190,360 Q 202,388 190,415 Q 215,415 228,388 Q 215,360 190,360 Z" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="204" y="391" font-size="9" font-weight="bold">OR</text>

  <line x1="228" y1="388" x2="310" y2="388" stroke="#000000" stroke-width="2" marker-end="url(#arrow)" />
  <text x="245" y="380" font-size="11" font-weight="bold">math_busy</text>


  <!-- ======================================================================== -->
  <!-- SECTION 2: PIPELINE STALL & FLUSH GENERATION (BOTTOM LEFT)               -->
  <!-- ======================================================================== -->
  <rect x="35" y="445" width="530" height="340" fill="#ffffff" stroke="#000000" stroke-width="1.5" stroke-dasharray="6,4" />
  <text x="45" y="465" font-size="13" font-weight="bold" fill="#000000">2. PIPELINE STALL &amp; FLUSH GENERATION LOGIC</text>

  <!-- Stall IF and IF/ID OR Gate -->
  <path d="M 170,490 Q 182,510 170,530 Q 192,510 205,510 Q 192,490 170,490 Z" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="183" y="513" font-size="9" font-weight="bold">OR</text>

  <!-- Route load_use_hazard and math_busy down -->
  <line x1="120" y1="498" x2="170" y2="498" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="45" y="502" font-size="10" font-weight="bold">load_use_hazard</text>
  <line x1="120" y1="522" x2="170" y2="522" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="45" y="526" font-size="10" font-weight="bold">math_busy</text>

  <line x1="205" y1="510" x2="260" y2="510" stroke="#000000" stroke-width="2" />
  <line x1="260" y1="510" x2="260" y2="495" stroke="#000000" stroke-width="2" />
  <line x1="260" y1="495" x2="350" y2="495" stroke="#000000" stroke-width="2" marker-end="url(#arrow)" />
  <text x="360" y="500" font-size="12" font-weight="bold" fill="#000000">stall_if &rarr; Freeze PC</text>

  <line x1="260" y1="510" x2="260" y2="525" stroke="#000000" stroke-width="2" />
  <line x1="260" y1="525" x2="350" y2="525" stroke="#000000" stroke-width="2" marker-end="url(#arrow)" />
  <text x="360" y="530" font-size="12" font-weight="bold" fill="#000000">stall_if_id &rarr; Freeze IF/ID Reg</text>

  <!-- stall_id_ex direct from math_busy -->
  <line x1="80" y1="522" x2="80" y2="555" stroke="#000000" stroke-width="1.5" />
  <line x1="80" y1="555" x2="350" y2="555" stroke="#000000" stroke-width="2" marker-end="url(#arrow)" />
  <circle cx="80" cy="522" r="3" fill="#000000" />
  <text x="360" y="560" font-size="12" font-weight="bold" fill="#000000">stall_id_ex &rarr; Freeze ID/EX Reg (Math Hold)</text>

  <!-- Inverter for !math_busy -->
  <line x1="80" y1="555" x2="80" y2="600" stroke="#000000" stroke-width="1.5" />
  <circle cx="80" cy="555" r="3" fill="#000000" />
  <line x1="80" y1="600" x2="110" y2="600" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <polygon points="110,590 110,610 128,600" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <circle cx="132" cy="600" r="3.5" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <line x1="136" y1="600" x2="160" y2="600" stroke="#000000" stroke-width="1.5" />
  <text x="145" y="590" font-size="10" font-weight="bold">!math_busy</text>

  <!-- flush_if_id: mispredict && !math_busy -->
  <text x="45" y="640" font-size="11" font-weight="bold">mispredict</text>
  <line x1="110" y1="635" x2="210" y2="635" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <line x1="160" y1="600" x2="180" y2="600" stroke="#000000" stroke-width="1.5" />
  <line x1="180" y1="600" x2="180" y2="620" stroke="#000000" stroke-width="1.5" />
  <line x1="180" y1="620" x2="210" y2="620" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />

  <path d="M 210,610 L 225,610 A 15,15 0 0,1 225,645 L 210,645 Z" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="222" y="630" font-size="10" font-weight="bold" text-anchor="middle">&amp;</text>
  <line x1="240" y1="628" x2="350" y2="628" stroke="#000000" stroke-width="2" marker-end="url(#arrow)" />
  <text x="360" y="633" font-size="12" font-weight="bold" fill="#000000">flush_if_id &rarr; Clear IF/ID Reg</text>

  <!-- flush_id_ex: (load_use_hazard || mispredict) && !math_busy -->
  <!-- OR for load_use || mispredict -->
  <line x1="90" y1="498" x2="90" y2="685" stroke="#000000" stroke-width="1.5" />
  <circle cx="90" cy="498" r="3" fill="#000000" />
  <line x1="90" y1="685" x2="130" y2="685" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />

  <line x1="120" y1="635" x2="120" y2="705" stroke="#000000" stroke-width="1.5" />
  <circle cx="120" cy="635" r="3" fill="#000000" />
  <line x1="120" y1="705" x2="130" y2="705" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />

  <path d="M 130,675 Q 142,695 130,715 Q 155,715 168,695 Q 155,675 130,675 Z" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="144" y="698" font-size="9" font-weight="bold">OR</text>

  <!-- AND with !math_busy -->
  <line x1="168" y1="695" x2="210" y2="695" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <line x1="180" y1="620" x2="180" y2="715" stroke="#000000" stroke-width="1.5" />
  <circle cx="180" cy="620" r="3" fill="#000000" />
  <line x1="180" y1="715" x2="210" y2="715" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />

  <path d="M 210,685 L 225,685 A 17,17 0 0,1 225,725 L 210,725 Z" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="222" y="708" font-size="10" font-weight="bold" text-anchor="middle">&amp;</text>
  <line x1="242" y1="705" x2="350" y2="705" stroke="#000000" stroke-width="2" marker-end="url(#arrow)" />
  <text x="360" y="710" font-size="12" font-weight="bold" fill="#000000">flush_id_ex &rarr; Clear ID/EX Reg (Bubble)</text>

  <!-- flush_ex_mem: math_busy -->
  <line x1="80" y1="600" x2="80" y2="755" stroke="#000000" stroke-width="1.5" />
  <circle cx="80" cy="600" r="3" fill="#000000" />
  <line x1="80" y1="755" x2="350" y2="755" stroke="#000000" stroke-width="2" marker-end="url(#arrow)" />
  <text x="360" y="760" font-size="12" font-weight="bold" fill="#000000">flush_ex_mem &rarr; Insert Bubble into EX/MEM Reg</text>


  <!-- ======================================================================== -->
  <!-- SECTION 3: DATA FORWARDING UNIT & EX-STAGE MUXES (RIGHT HALF)            -->
  <!-- ======================================================================== -->
  <rect x="580" y="90" width="545" height="695" fill="#ffffff" stroke="#000000" stroke-width="1.5" stroke-dasharray="6,4" />
  <text x="590" y="110" font-size="13" font-weight="bold" fill="#000000">3. DATA FORWARDING UNIT (OPERAND A &amp; OPERAND B)</text>

  <!-- SUB-BLOCK A: FORWARD A -->
  <rect x="595" y="125" width="515" height="315" fill="#ffffff" stroke="#000000" stroke-width="1" />
  <text x="605" y="145" font-size="12" font-weight="bold">A. Operand A Forwarding Logic (RS1 Bypass)</text>

  <!-- Inputs for Forward A -->
  <text x="605" y="175" font-size="10" font-weight="bold">ex_mem_rd[4:0]</text>
  <text x="605" y="195" font-size="10" font-weight="bold">id_ex_rs1[4:0]</text>
  <text x="605" y="215" font-size="10" font-weight="bold">ex_mem_reg_write</text>

  <rect x="710" y="165" width="55" height="30" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="737" y="184" font-size="11" font-weight="bold" text-anchor="middle">==</text>
  <line x1="680" y1="175" x2="710" y2="175" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <line x1="680" y1="190" x2="710" y2="190" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />

  <text x="605" y="250" font-size="10" font-weight="bold">mem_wb_rd[4:0]</text>
  <text x="605" y="270" font-size="10" font-weight="bold">mem_wb_reg_write</text>

  <rect x="710" y="240" width="55" height="30" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="737" y="259" font-size="11" font-weight="bold" text-anchor="middle">==</text>
  <line x1="680" y1="245" x2="710" y2="245" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <line x1="680" y1="190" x2="695" y2="190" stroke="#000000" stroke-width="1.5" />
  <line x1="695" y1="190" x2="695" y2="260" stroke="#000000" stroke-width="1.5" />
  <circle cx="695" cy="190" r="3" fill="#000000" />
  <line x1="695" y1="260" x2="710" y2="260" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />

  <!-- Priority Encoder Box for forward_a -->
  <rect x="790" y="160" width="115" height="115" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="847" y="180" font-size="11" font-weight="bold" text-anchor="middle">PRIORITY</text>
  <text x="847" y="195" font-size="11" font-weight="bold" text-anchor="middle">ENCODER</text>
  <text x="847" y="215" font-size="9" text-anchor="middle">1. EX/MEM (10)</text>
  <text x="847" y="230" font-size="9" text-anchor="middle">2. MEM/WB (01)</text>
  <text x="847" y="245" font-size="9" text-anchor="middle">3. NONE (00)</text>

  <line x1="765" y1="180" x2="790" y2="180" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <line x1="765" y1="255" x2="790" y2="255" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />

  <!-- Output forward_a[1:0] -->
  <line x1="905" y1="215" x2="960" y2="215" stroke="#000000" stroke-width="2" marker-end="url(#arrow)" />
  <text x="915" y="205" font-size="10" font-weight="bold">forward_a[1:0]</text>

  <!-- 3-to-1 Multiplexer for Operand A -->
  <polygon points="965,160 1025,185 1025,285 965,310" fill="#ffffff" stroke="#000000" stroke-width="2" />
  <text x="995" y="238" font-size="12" font-weight="bold" text-anchor="middle">MUX A</text>

  <text x="930" y="180" font-size="9">ID/EX rdata1</text>
  <line x1="935" y1="185" x2="965" y2="185" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="970" y="190" font-size="9">00</text>

  <text x="910" y="235" font-size="9">WB Result (01)</text>
  <line x1="935" y1="235" x2="965" y2="235" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="970" y="240" font-size="9">01</text>

  <text x="910" y="285" font-size="9">MEM ALU Res (10)</text>
  <line x1="935" y1="285" x2="965" y2="285" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="970" y="290" font-size="9">10</text>

  <line x1="995" y1="150" x2="995" y2="173" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="995" y="145" font-size="9" text-anchor="middle">sel: forward_a[1:0]</text>

  <line x1="1025" y1="235" x2="1080" y2="235" stroke="#000000" stroke-width="2" marker-end="url(#arrow)" />
  <text x="1030" y="225" font-size="10" font-weight="bold">ALU Operand 1</text>


  <!-- SUB-BLOCK B: FORWARD B -->
  <rect x="595" y="455" width="515" height="315" fill="#ffffff" stroke="#000000" stroke-width="1" />
  <text x="605" y="475" font-size="12" font-weight="bold">B. Operand B Forwarding Logic (RS2 Bypass)</text>

  <!-- Inputs for Forward B -->
  <text x="605" y="505" font-size="10" font-weight="bold">ex_mem_rd[4:0]</text>
  <text x="605" y="525" font-size="10" font-weight="bold">id_ex_rs2[4:0]</text>
  <text x="605" y="545" font-size="10" font-weight="bold">ex_mem_reg_write</text>

  <rect x="710" y="495" width="55" height="30" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="737" y="514" font-size="11" font-weight="bold" text-anchor="middle">==</text>
  <line x1="680" y1="505" x2="710" y2="505" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <line x1="680" y1="520" x2="710" y2="520" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />

  <text x="605" y="580" font-size="10" font-weight="bold">mem_wb_rd[4:0]</text>
  <text x="605" y="600" font-size="10" font-weight="bold">mem_wb_reg_write</text>

  <rect x="710" y="570" width="55" height="30" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="737" y="589" font-size="11" font-weight="bold" text-anchor="middle">==</text>
  <line x1="680" y1="575" x2="710" y2="575" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <line x1="680" y1="520" x2="695" y2="520" stroke="#000000" stroke-width="1.5" />
  <line x1="695" y1="520" x2="695" y2="590" stroke="#000000" stroke-width="1.5" />
  <circle cx="695" cy="520" r="3" fill="#000000" />
  <line x1="695" y1="590" x2="710" y2="590" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />

  <!-- Priority Encoder Box for forward_b -->
  <rect x="790" y="490" width="115" height="115" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="847" y="510" font-size="11" font-weight="bold" text-anchor="middle">PRIORITY</text>
  <text x="847" y="525" font-size="11" font-weight="bold" text-anchor="middle">ENCODER</text>
  <text x="847" y="545" font-size="9" text-anchor="middle">1. EX/MEM (10)</text>
  <text x="847" y="560" font-size="9" text-anchor="middle">2. MEM/WB (01)</text>
  <text x="847" y="575" font-size="9" text-anchor="middle">3. NONE (00)</text>

  <line x1="765" y1="510" x2="790" y2="510" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <line x1="765" y1="585" x2="790" y2="585" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />

  <!-- Output forward_b[1:0] -->
  <line x1="905" y1="545" x2="960" y2="545" stroke="#000000" stroke-width="2" marker-end="url(#arrow)" />
  <text x="915" y="535" font-size="10" font-weight="bold">forward_b[1:0]</text>

  <!-- 3-to-1 Multiplexer for Operand B -->
  <polygon points="965,490 1025,515 1025,615 965,640" fill="#ffffff" stroke="#000000" stroke-width="2" />
  <text x="995" y="568" font-size="12" font-weight="bold" text-anchor="middle">MUX B</text>

  <text x="930" y="510" font-size="9">ID/EX rdata2</text>
  <line x1="935" y1="515" x2="965" y2="515" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="970" y="520" font-size="9">00</text>

  <text x="910" y="565" font-size="9">WB Result (01)</text>
  <line x1="935" y1="565" x2="965" y2="565" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="970" y="570" font-size="9">01</text>

  <text x="910" y="615" font-size="9">MEM ALU Res (10)</text>
  <line x1="935" y1="615" x2="965" y2="615" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="970" y="620" font-size="9">10</text>

  <line x1="995" y1="480" x2="995" y2="503" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="995" y="475" font-size="9" text-anchor="middle">sel: forward_b[1:0]</text>

  <line x1="1025" y1="565" x2="1080" y2="565" stroke="#000000" stroke-width="2" marker-end="url(#arrow)" />
  <text x="1030" y="555" font-size="10" font-weight="bold">ALU Operand 2</text>

</svg>
"""

# ==============================================================================
# 2. BTB ARCHITECTURE SVG DEFINITION
# ==============================================================================
svg_btb_arch = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1150 820" width="100%" height="100%" style="background-color: #ffffff; font-family: Arial, Helvetica, sans-serif;">
  <defs>
    <!-- Arrowhead markers -->
    <marker id="arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 1.5 L 8 5 L 0 8.5 z" fill="#000000" />
    </marker>
    <marker id="dot" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="4" markerHeight="4">
      <circle cx="5" cy="5" r="3" fill="#000000" />
    </marker>
  </defs>

  <!-- Title & Border -->
  <rect x="15" y="15" width="1120" height="790" fill="#ffffff" stroke="#000000" stroke-width="2.5" />
  <text x="575" y="45" font-size="18" font-weight="bold" text-anchor="middle" fill="#000000" letter-spacing="0.5">BRANCH TARGET BUFFER (BTB) &amp; SPECULATIVE RESOLUTION ARCHITECTURE</text>
  <text x="575" y="65" font-size="12" font-style="italic" text-anchor="middle" fill="#333333">Cycle-Accurate Hardware Block Diagram &bull; Query Path (IF), Pipeline Propagation, and EX-Stage Resolution</text>
  <line x1="15" y1="75" x2="1135" y2="75" stroke="#000000" stroke-width="1.5" />

  <!-- ======================================================================== -->
  <!-- ZONE 1: INSTRUCTION FETCH (IF) STAGE & BTB QUERY PATH                    -->
  <!-- ======================================================================== -->
  <rect x="35" y="90" width="460" height="695" fill="#ffffff" stroke="#000000" stroke-width="1.5" stroke-dasharray="6,4" />
  <text x="45" y="112" font-size="13" font-weight="bold">ZONE 1: FETCH STAGE (IF) &mdash; ZERO-CYCLE BTB QUERY</text>

  <!-- Program Counter Register (pc_reg) -->
  <rect x="55" y="230" width="80" height="80" fill="#ffffff" stroke="#000000" stroke-width="2" />
  <text x="95" y="265" font-size="12" font-weight="bold" text-anchor="middle">PC REG</text>
  <text x="95" y="285" font-size="9" text-anchor="middle">32-bit</text>
  <polygon points="55,290 65,295 55,300" fill="#000000" />
  <text x="95" y="325" font-size="9" text-anchor="middle">clk / stall_if</text>

  <!-- Output of PC REG: fetch_pc[31:0] -->
  <line x1="135" y1="270" x2="185" y2="270" stroke="#000000" stroke-width="2" marker-end="url(#arrow)" />
  <text x="140" y="260" font-size="10" font-weight="bold">fetch_pc[31:0]</text>

  <!-- Address Decomposition Block -->
  <rect x="185" y="225" width="115" height="150" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="242" y="245" font-size="11" font-weight="bold" text-anchor="middle">ADDRESS</text>
  <text x="242" y="260" font-size="11" font-weight="bold" text-anchor="middle">DECODER</text>
  <line x1="185" y1="270" x2="300" y2="270" stroke="#000000" stroke-width="1" />
  <text x="195" y="295" font-size="10">Tag [31:7]</text>
  <text x="195" y="325" font-size="10" font-weight="bold">Idx [6:2]</text>
  <text x="195" y="355" font-size="9" fill="#555555">[1:0] = 00</text>

  <!-- PC + 4 Adder -->
  <line x1="160" y1="270" x2="160" y2="150" stroke="#000000" stroke-width="1.5" />
  <circle cx="160" cy="270" r="3" fill="#000000" />
  <line x1="160" y1="150" x2="200" y2="150" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />

  <polygon points="200,130 250,140 250,180 200,190" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="225" y="163" font-size="16" font-weight="bold" text-anchor="middle">+</text>
  <text x="202" y="178" font-size="9">4</text>
  <line x1="250" y1="160" x2="390" y2="160" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="270" y="152" font-size="10" font-weight="bold">pc_plus4 [31:0]</text>

  <!-- 32-Entry BTB Memory Block -->
  <rect x="330" y="260" width="150" height="230" fill="#ffffff" stroke="#000000" stroke-width="2" />
  <text x="405" y="285" font-size="12" font-weight="bold" text-anchor="middle">32-ENTRY BTB</text>
  <text x="405" y="302" font-size="9" text-anchor="middle">(Direct-Mapped SRAM)</text>
  <line x1="330" y1="310" x2="480" y2="310" stroke="#000000" stroke-width="1" />

  <!-- Sub-arrays inside BTB -->
  <rect x="340" y="320" width="130" height="40" fill="#ffffff" stroke="#000000" stroke-width="1" />
  <text x="405" y="340" font-size="10" font-weight="bold" text-anchor="middle">Valid Array (32x1b)</text>
  <text x="405" y="352" font-size="8" text-anchor="middle">1 = Allocated Branch</text>

  <rect x="340" y="370" width="130" height="45" fill="#ffffff" stroke="#000000" stroke-width="1" />
  <text x="405" y="390" font-size="10" font-weight="bold" text-anchor="middle">Tag Array (32x25b)</text>
  <text x="405" y="405" font-size="8" text-anchor="middle">Stores PC[31:7]</text>

  <rect x="340" y="425" width="130" height="55" fill="#ffffff" stroke="#000000" stroke-width="1" />
  <text x="405" y="445" font-size="10" font-weight="bold" text-anchor="middle">Target Array (32x32b)</text>
  <text x="405" y="460" font-size="8" text-anchor="middle">Cached Target Address</text>

  <!-- Route Index [6:2] into BTB Read Port -->
  <line x1="300" y1="325" x2="330" y2="325" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="303" y="318" font-size="9">/5</text>

  <!-- Route Tag Array output & Fetch Tag to Tag Comparator -->
  <line x1="470" y1="390" x2="470" y2="525" stroke="#000000" stroke-width="1.5" />
  <line x1="470" y1="525" x2="400" y2="525" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />

  <line x1="300" y1="295" x2="315" y2="295" stroke="#000000" stroke-width="1.5" />
  <line x1="315" y1="295" x2="315" y2="540" stroke="#000000" stroke-width="1.5" />
  <line x1="315" y1="540" x2="340" y2="540" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="317" y="533" font-size="9">/25</text>

  <!-- Tag Comparator (25-bit Equality) -->
  <rect x="340" y="515" width="60" height="35" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="370" y="537" font-size="12" font-weight="bold" text-anchor="middle">==</text>
  <text x="370" y="510" font-size="8" text-anchor="middle">25b Match</text>

  <!-- AND Gate for btb_hit: valid && tag_match -->
  <line x1="400" y1="532" x2="435" y2="532" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <line x1="340" y1="340" x2="325" y2="340" stroke="#000000" stroke-width="1.5" />
  <line x1="325" y1="340" x2="325" y2="550" stroke="#000000" stroke-width="1.5" />
  <line x1="325" y1="550" x2="435" y2="550" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />

  <path d="M 435,522 L 450,522 A 16,16 0 0,1 450,560 L 435,560 Z" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="446" y="545" font-size="10" font-weight="bold" text-anchor="middle">&amp;</text>

  <!-- btb_hit Wire -->
  <line x1="466" y1="541" x2="495" y2="541" stroke="#000000" stroke-width="2" />
  <text x="470" y="532" font-size="10" font-weight="bold">btb_hit</text>

  <!-- 2-to-1 MUX for pred_target -->
  <polygon points="390,610 435,620 435,680 390,690" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="412" y="655" font-size="10" font-weight="bold" text-anchor="middle">MUX</text>

  <!-- Input 0: fetch_pc + 4 -->
  <line x1="280" y1="160" x2="280" y2="630" stroke="#000000" stroke-width="1.5" />
  <circle cx="280" cy="160" r="3" fill="#000000" />
  <line x1="280" y1="630" x2="390" y2="630" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="375" y="625" font-size="9">0</text>

  <!-- Input 1: target_array[index] -->
  <line x1="470" y1="460" x2="480" y2="460" stroke="#000000" stroke-width="1.5" />
  <line x1="480" y1="460" x2="480" y2="670" stroke="#000000" stroke-width="1.5" />
  <line x1="480" y1="670" x2="435" y2="670" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="375" y="675" font-size="9">1</text>

  <!-- Select for pred_target MUX: btb_hit -->
  <line x1="475" y1="541" x2="475" y2="600" stroke="#000000" stroke-width="1.5" />
  <circle cx="475" cy="541" r="3" fill="#000000" />
  <line x1="475" y1="600" x2="412" y2="600" stroke="#000000" stroke-width="1.5" />
  <line x1="412" y1="600" x2="412" y2="615" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="415" y="595" font-size="8">sel: btb_hit</text>

  <!-- Output of pred_target MUX -->
  <line x1="435" y1="650" x2="520" y2="650" stroke="#000000" stroke-width="2" marker-end="url(#arrow)" />
  <text x="440" y="642" font-size="10" font-weight="bold">pred_target[31:0]</text>

  <!-- NEXT PC 3-to-1 PRIORITIZED MUX -->
  <polygon points="55,140 115,160 115,220 55,240" fill="#ffffff" stroke="#000000" stroke-width="2" />
  <text x="85" y="195" font-size="11" font-weight="bold" text-anchor="middle">PC MUX</text>

  <!-- Input 0: pc_plus4 -->
  <line x1="280" y1="160" x2="280" y2="120" stroke="#000000" stroke-width="1.5" />
  <line x1="280" y1="120" x2="40" y2="120" stroke="#000000" stroke-width="1.5" />
  <line x1="40" y1="120" x2="40" y2="170" stroke="#000000" stroke-width="1.5" />
  <line x1="40" y1="170" x2="55" y2="170" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="43" y="165" font-size="9">00</text>
  <text x="42" y="152" font-size="8">pc+4</text>

  <!-- Input 1: pred_target (when pred_hit) -->
  <line x1="495" y1="650" x2="495" y2="740" stroke="#000000" stroke-width="1.5" />
  <circle cx="495" cy="650" r="3" fill="#000000" />
  <line x1="495" y1="740" x2="45" y2="740" stroke="#000000" stroke-width="1.5" />
  <line x1="45" y1="740" x2="45" y2="190" stroke="#000000" stroke-width="1.5" />
  <line x1="45" y1="190" x2="55" y2="190" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="45" y="185" font-size="9">01</text>
  <text x="35" y="202" font-size="8">pred_tgt</text>

  <!-- Input 2: ex_redirect_pc (HIGHEST PRIORITY on Mispredict) -->
  <line x1="55" y1="210" x2="30" y2="210" stroke="#000000" stroke-width="1.5" />
  <text x="45" y="222" font-size="9">10</text>
  <text x="18" y="235" font-size="8">redirect</text>

  <!-- Output of PC MUX to PC REG -->
  <line x1="115" y1="190" x2="130" y2="190" stroke="#000000" stroke-width="2" />
  <line x1="130" y1="190" x2="130" y2="215" stroke="#000000" stroke-width="2" />
  <line x1="130" y1="215" x2="95" y2="215" stroke="#000000" stroke-width="2" />
  <line x1="95" y1="215" x2="95" y2="230" stroke="#000000" stroke-width="2" marker-end="url(#arrow)" />
  <text x="100" y="210" font-size="9" font-weight="bold">pc_next[31:0]</text>


  <!-- ======================================================================== -->
  <!-- ZONE 2: PIPELINE SYNCHRONOUS PROPAGATION (IF/ID -> ID/EX)                -->
  <!-- ======================================================================== -->
  <rect x="510" y="90" width="130" height="695" fill="#ffffff" stroke="#000000" stroke-width="1.5" stroke-dasharray="6,4" />
  <text x="575" y="112" font-size="12" font-weight="bold" text-anchor="middle">ZONE 2: PIPELINE</text>
  <text x="575" y="126" font-size="10" font-style="italic" text-anchor="middle">Metadata Carriage</text>

  <!-- IF/ID Register Block -->
  <rect x="525" y="200" width="100" height="150" fill="#ffffff" stroke="#000000" stroke-width="2" />
  <text x="575" y="225" font-size="11" font-weight="bold" text-anchor="middle">IF/ID REG</text>
  <line x1="525" y1="235" x2="625" y2="235" stroke="#000000" stroke-width="1" />
  <text x="535" y="255" font-size="9">pred_taken</text>
  <text x="535" y="280" font-size="9">pred_target[31:0]</text>
  <text x="535" y="305" font-size="9">instr[31:0]</text>
  <text x="535" y="330" font-size="9">pc[31:0]</text>

  <!-- ID/EX Register Block -->
  <rect x="525" y="440" width="100" height="170" fill="#ffffff" stroke="#000000" stroke-width="2" />
  <text x="575" y="465" font-size="11" font-weight="bold" text-anchor="middle">ID/EX REG</text>
  <line x1="525" y1="475" x2="625" y2="475" stroke="#000000" stroke-width="1" />
  <text x="535" y="495" font-size="9">pred_taken</text>
  <text x="535" y="520" font-size="9">pred_target[31:0]</text>
  <text x="535" y="545" font-size="9">rdata1 / rdata2</text>
  <text x="535" y="570" font-size="9">imm_b / imm_j</text>
  <text x="535" y="595" font-size="9">branch/jal/jalr</text>

  <!-- Route from IF into IF/ID Reg -->
  <line x1="495" y1="541" x2="525" y2="541" stroke="#000000" stroke-width="1.5" />
  <!-- Wire down to registers -->
  <line x1="575" y1="350" x2="575" y2="440" stroke="#000000" stroke-width="2" marker-end="url(#arrow)" />
  <text x="580" y="395" font-size="9" font-style="italic">Synchronous</text>
  <text x="580" y="410" font-size="9" font-style="italic">Clock Edge</text>


  <!-- ======================================================================== -->
  <!-- ZONE 3: EXECUTE STAGE (EX) & RESOLUTION HARDWARE                         -->
  <!-- ======================================================================== -->
  <rect x="655" y="90" width="470" height="695" fill="#ffffff" stroke="#000000" stroke-width="1.5" stroke-dasharray="6,4" />
  <text x="665" y="112" font-size="13" font-weight="bold">ZONE 3: EXECUTE STAGE (EX) &mdash; RESOLUTION &amp; RECOVERY</text>

  <!-- Actual Branch Target Adder: pc_i + imm_b -->
  <polygon points="685,150 735,160 735,200 685,210" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="710" y="183" font-size="16" font-weight="bold" text-anchor="middle">+</text>
  <text x="665" y="165" font-size="9">pc_ex</text>
  <text x="665" y="195" font-size="9">imm_b</text>

  <!-- Actual JALR Target Adder: rs1 + imm_i -->
  <polygon points="685,230 735,240 735,280 685,290" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="710" y="263" font-size="16" font-weight="bold" text-anchor="middle">+</text>
  <text x="665" y="245" font-size="9">rs1_fwd</text>
  <text x="665" y="275" font-size="9">imm_i</text>

  <!-- 2-to-1 MUX for actual target_pc_o -->
  <polygon points="770,180 810,195 810,245 770,260" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="790" y="224" font-size="10" font-weight="bold" text-anchor="middle">MUX</text>
  <line x1="735" y1="180" x2="770" y2="180" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="755" y="175" font-size="8">0: br/jal</text>
  <line x1="735" y1="260" x2="770" y2="260" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="755" y="255" font-size="8">1: jalr</text>
  <line x1="790" y1="165" x2="790" y2="188" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="795" y="160" font-size="8">sel: jalr_i</text>

  <line x1="810" y1="220" x2="860" y2="220" stroke="#000000" stroke-width="2" />
  <text x="815" y="210" font-size="10" font-weight="bold">target_pc_o[31:0]</text>

  <!-- Branch Condition Evaluator (ALU Comparator) -->
  <rect x="685" y="315" width="105" height="50" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="737" y="335" font-size="10" font-weight="bold" text-anchor="middle">BRANCH COND</text>
  <text x="737" y="352" font-size="9" text-anchor="middle">EVALUATOR (ALU)</text>

  <!-- Actual branch_or_jump_taken_o Logic -->
  <path d="M 830,330 Q 842,350 830,370 Q 855,370 870,350 Q 855,330 830,330 Z" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="845" y="353" font-size="9" font-weight="bold">OR</text>
  <line x1="790" y1="340" x2="830" y2="340" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="685" y="385" font-size="9">jal_i || jalr_i</text>
  <line x1="740" y1="380" x2="815" y2="380" stroke="#000000" stroke-width="1.5" />
  <line x1="815" y1="380" x2="835" y2="360" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />

  <line x1="870" y1="350" x2="910" y2="350" stroke="#000000" stroke-width="2" />
  <text x="875" y="340" font-size="10" font-weight="bold">actual_taken</text>

  <!-- MISPREDICTION EVALUATOR BLOCK -->
  <rect x="880" y="390" width="230" height="175" fill="#ffffff" stroke="#000000" stroke-width="2" />
  <text x="995" y="415" font-size="12" font-weight="bold" text-anchor="middle">MISPREDICT DETECTOR</text>
  <line x1="880" y1="425" x2="1110" y2="425" stroke="#000000" stroke-width="1" />

  <!-- Direction check: actual_taken != pred_taken_i -->
  <rect x="895" y="440" width="55" height="30" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="922" y="460" font-size="12" font-weight="bold" text-anchor="middle">!=</text>
  <text x="922" y="435" font-size="8" text-anchor="middle">Direction</text>

  <!-- Target check: target_pc_o != pred_target_i -->
  <rect x="895" y="490" width="55" height="30" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="922" y="510" font-size="12" font-weight="bold" text-anchor="middle">!=</text>
  <text x="922" y="485" font-size="8" text-anchor="middle">Target 32b</text>

  <line x1="950" y1="455" x2="990" y2="455" stroke="#000000" stroke-width="1.5" />
  <line x1="950" y1="505" x2="975" y2="505" stroke="#000000" stroke-width="1.5" />
  <line x1="975" y1="505" x2="975" y2="475" stroke="#000000" stroke-width="1.5" />
  <line x1="975" y1="475" x2="990" y2="475" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />

  <!-- OR inside Mispredict block -->
  <path d="M 990,450 Q 1000,465 990,480 Q 1010,480 1020,465 Q 1010,450 990,450 Z" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="1002" y="468" font-size="8" font-weight="bold">OR</text>

  <!-- Gate with update_en -->
  <line x1="1020" y1="465" x2="1045" y2="465" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <path d="M 1045,455 L 1060,455 A 15,15 0 0,1 1060,485 L 1045,485 Z" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="1055" y="473" font-size="9" font-weight="bold" text-anchor="middle">&amp;</text>

  <!-- Output mispredict_o -->
  <line x1="1075" y1="470" x2="1110" y2="470" stroke="#000000" stroke-width="2.5" marker-end="url(#arrow)" />
  <text x="1000" y="555" font-size="12" font-weight="bold" fill="#000000">mispredict_o</text>

  <!-- RECOVERY REDIRECT MUX -->
  <polygon points="720,590 760,605 760,665 720,680" fill="#ffffff" stroke="#000000" stroke-width="1.5" />
  <text x="740" y="638" font-size="10" font-weight="bold" text-anchor="middle">MUX</text>
  <text x="740" y="580" font-size="8" text-anchor="middle">sel: actual_taken</text>

  <!-- 0: pc_plus4_i (if branch not taken) -->
  <text x="665" y="610" font-size="9">pc_plus4_i</text>
  <line x1="710" y1="610" x2="720" y2="610" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="725" y="615" font-size="8">0</text>

  <!-- 1: target_pc_o (if branch taken) -->
  <text x="665" y="660" font-size="9">target_pc_o</text>
  <line x1="710" y1="660" x2="720" y2="660" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="725" y="665" font-size="8">1</text>

  <line x1="760" y1="635" x2="810" y2="635" stroke="#000000" stroke-width="2" marker-end="url(#arrow)" />
  <text x="815" y="630" font-size="10" font-weight="bold">redirect_pc_o[31:0]</text>

  <!-- FEEDBACK LOOPS TO IF STAGE -->
  <!-- 1. mispredict_o loop to Hazard Unit & Next-PC MUX -->
  <line x1="1090" y1="470" x2="1090" y2="760" stroke="#000000" stroke-width="1.5" />
  <circle cx="1090" cy="470" r="3" fill="#000000" />
  <line x1="1090" y1="760" x2="20" y2="760" stroke="#000000" stroke-width="1.5" />
  <line x1="20" y1="760" x2="20" y2="210" stroke="#000000" stroke-width="1.5" />
  <line x1="20" y1="210" x2="30" y2="210" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)" />
  <text x="25" y="750" font-size="9" font-weight="bold">mispredict recovery loop</text>

  <!-- 2. BTB WRITE PORT SIGNALS ON CLOCK EDGE -->
  <rect x="675" y="700" width="430" height="70" fill="#ffffff" stroke="#000000" stroke-width="1.5" stroke-dasharray="4,3" />
  <text x="685" y="720" font-size="10" font-weight="bold">BTB SYNCHRONOUS WRITE INTERFACE (from EX Stage on Clock Edge):</text>
  <text x="685" y="738" font-size="9">&bull; update_en = (branch || jal || jalr) &nbsp;&nbsp;|&nbsp;&nbsp; update_index = pc_ex[6:2] (5b)</text>
  <text x="685" y="755" font-size="9">&bull; update_taken ? [valid=1, tag=pc_ex[31:7], target=target_pc_o] : [valid=0 (Invalidate)]</text>

</svg>
"""

# ==============================================================================
# WRITE INDIVIDUAL SVG FILES (CLEAN BLACK ON WHITE)
# ==============================================================================
workspace_dir = r"C:\CS2202L\RISCV"
artifact_dir = r"C:\Users\prane\.gemini\antigravity\brain\bf6ec4b6-a6a1-477d-9aa5-79f87341bfc8"

hazard_svg_path = os.path.join(workspace_dir, "hazard_unit_block_diagram.svg")
btb_svg_path = os.path.join(workspace_dir, "btb_architecture_block_diagram.svg")

with open(hazard_svg_path, "w", encoding="utf-8") as f:
    f.write(svg_hazard_unit)
print(f"Written: {hazard_svg_path}")

with open(btb_svg_path, "w", encoding="utf-8") as f:
    f.write(svg_btb_arch)
print(f"Written: {btb_svg_path}")

# ==============================================================================
# 3. BUILD PRESENTATION-READY PDF CONTAINING BOTH SCHEMATICS
# ==============================================================================
html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Hazard Unit and BTB Hardware Schematics</title>
<style>
    @page {{
        size: A4 landscape;
        margin: 10mm 10mm 10mm 10mm;
        @bottom-right {{
            content: "Page " counter(page);
            font-size: 8pt;
            font-family: Arial, sans-serif;
            color: #555555;
        }}
    }}

    body {{
        margin: 0;
        padding: 0;
        background-color: #ffffff;
        color: #000000;
        font-family: Arial, Helvetica, sans-serif;
    }}

    .page {{
        width: 100%;
        height: 100vh;
        page-break-after: always;
        display: flex;
        flex-direction: column;
        justify-content: flex-start;
        align-items: center;
        background: #ffffff;
    }}

    .page:last-child {{
        page-break-after: avoid;
    }}

    .diagram-wrap {{
        width: 100%;
        max-width: 1100px;
        margin: auto;
    }}
</style>
</head>
<body>

<div class="page">
    <div class="diagram-wrap">
        {svg_hazard_unit}
    </div>
</div>

<div class="page">
    <div class="diagram-wrap">
        {svg_btb_arch}
    </div>
</div>

</body>
</html>
"""

html_file = os.path.join(workspace_dir, "schematics_render.html")
pdf_workspace = os.path.join(workspace_dir, "Hazard_Unit_and_BTB_Block_Diagrams.pdf")
pdf_artifact = os.path.join(artifact_dir, "Hazard_Unit_and_BTB_Block_Diagrams.pdf")

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

print("Rendering Black-and-White PDF via Microsoft Edge Headless...")
subprocess.run(cmd, check=True)

if os.path.exists(pdf_workspace):
    size_kb = os.path.getsize(pdf_workspace) / 1024
    print(f"Generated PDF in workspace: {pdf_workspace} ({size_kb:.1f} KB)")
    shutil.copyfile(pdf_workspace, pdf_artifact)
    print(f"Copied PDF to artifact directory: {pdf_artifact}")
    if os.path.exists(html_file):
        os.remove(html_file)
else:
    print("Error: PDF was not generated.")
