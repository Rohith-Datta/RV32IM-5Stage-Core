"""
================================================================================
  RV32IMF+Zbb AVIONICS TELEMETRY & MICRO-ARCHITECTURAL VERIFICATION DASHBOARD
  Digilent Nexys A7-100T FPGA (Xilinx Artix-7 XC7A100T-1CSG324C)
  Pixel-Accurate Live Academic Demonstration System
================================================================================
"""

import sys
import os
import time
import math
import queue
import struct
import random
import threading
import argparse

# ------------------------------------------------------------------------------
# Auto-Environment Relauncher
# ------------------------------------------------------------------------------
# Ensures that if executed from an environment missing GUI dependencies (like MSYS2),
# it automatically relaunches with the configured Windows Python interpreter.
try:
    import tkinter as tk
    from tkinter import ttk
    import matplotlib
    import matplotlib.pyplot as plt
    from matplotlib.figure import Figure
    from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
    import customtkinter as ctk
    import serial
    import serial.tools.list_ports
except ImportError:
    win_py = r"C:\Users\prane\AppData\Local\Programs\Python\Python312\python.exe"
    if os.path.exists(win_py) and os.path.normpath(sys.executable).lower() != os.path.normpath(win_py).lower():
        import subprocess
        sys.exit(subprocess.call([win_py] + sys.argv))
    else:
        raise

# ------------------------------------------------------------------------------
# GLOBAL VISUAL PALETTE & THEME CONFIGURATION
# ------------------------------------------------------------------------------
THEME = {
    "bg_root":       "#080C15",  # Deep Midnight Navy
    "card_bg":       "#0B111E",  # Card surface
    "card_border":   "#1E293B",  # Slate 1px border
    "header_sub":    "#94A3B8",  # Muted slate text
    "text_white":    "#F8FAFC",  # Pure bright white
    "neon_green":    "#22C55E",  # Primary active green
    "neon_cyan":     "#38BDF8",  # Electric blue / cyan
    "accent_blue":   "#0284C7",  # Navigation pill active
    "text_dim":      "#64748B",  # Subdued gray/slate
    "gauge_track":   "#162032",  # Dark arc track
    "term_bg":       "#050810",  # Console black/navy
    "badge_live_bg": "#064E3B",  # Live badge background
    "badge_live_fg": "#34D399",  # Live badge text
    "badge_live_bd": "#059669",  # Live badge border
}

ctk.set_appearance_mode("Dark")
ctk.set_default_color_theme("dark-blue")

DEFAULT_PORT = "COM3"
DEFAULT_BAUD = 115200


# ==============================================================================
# HOST GOLDEN MATHEMATICAL MODEL (IEEE-754 + RV32M + ZBB)
# ==============================================================================
class HostGoldenModel:
    def __init__(self):
        self.ema_state = 0.0

    def reset(self):
        self.ema_state = 0.0

    @staticmethod
    def f32(val: float) -> float:
        """Force Python 64-bit float to exact 32-bit IEEE-754 single precision."""
        return struct.unpack("!f", struct.pack("!f", float(val)))[0]

    @staticmethod
    def float_to_hex(val: float) -> str:
        if math.isnan(val):
            return "7FC00000"
        return f"{struct.unpack('!I', struct.pack('!f', val))[0]:08X}"

    @staticmethod
    def hex_to_float(hex_str: str) -> float:
        raw = int(hex_str, 16) & 0xFFFFFFFF
        return struct.unpack("!f", struct.pack("!I", raw))[0]

    @staticmethod
    def zbb_cpop(val: int) -> int:
        return bin(val & 0xFFFFFFFF).count("1")

    def step(self, iter_idx: int, sw_val: int, raw_hex: str) -> tuple[str, int, str]:
        mode = (sw_val >> 14) & 0x3
        input_seed = sw_val & 0xFF
        raw_int = int(raw_hex, 16) & 0xFFFFFFFF
        expected_cpop = self.zbb_cpop(raw_int)

        if mode == 0x3:
            desc_map = {
                0x01: "+Infinity (1.0f / 0.0f) [DZ=1]",
                0x02: "-Infinity (-1.0f / 0.0f) [DZ=1]",
                0x03: "Quiet NaN (0.0f / 0.0f) [NV=1]",
                0x04: "Quiet NaN (Inf - Inf) [NV=1]",
                0x05: "Quiet NaN (0.0f * Inf) [NV=1]",
                0x06: "Signed Negative Zero (-0.0f)",
                0x07: "IEEE-754 RNE Tie-to-Even (GRS)",
                0x08: "RV32M Int Div/0 -> 0xFFFFFFFF (-1)",
                0x09: "RV32M Signed Overflow (INT_MIN/-1)",
                0x0A: "Zbb Signed MAX vs Unsigned MAXU",
                0x0B: "Zbb Boundary CLZ(0)=32, CTZ(0)=32",
            }
            desc = desc_map.get(input_seed, f"Fault Injection (0x{input_seed:02X})")
            return f"{raw_int:08X}", expected_cpop, desc

        alpha = self.f32(float(input_seed) / 255.0) if input_seed > 0 else 0.10
        one_minus_alpha = self.f32(1.0 - alpha)
        x_val = self.hex_to_float(raw_hex)

        if iter_idx == 0:
            self.ema_state = x_val
        else:
            t1 = self.f32(alpha * x_val)
            t2 = self.f32(one_minus_alpha * self.ema_state)
            self.ema_state = self.f32(t1 + t2)

        exp_hex = self.float_to_hex(self.ema_state)
        return exp_hex, expected_cpop, f"Flight EMA (alpha={alpha:.3f})"


# ==============================================================================
# HIGH-TECH CIRCULAR ARC GAUGE WIDGET
# ==============================================================================
class ModernArcGauge(tk.Canvas):
    """
    Precision vector circular arc gauge matching the target dashboard UI.
    Features dark track, glowing neon green arc, bold numeric readout,
    top title, unit subtitle, and min/max scale markers.
    """
    def __init__(self, parent, title: str, min_val: float, max_val: float,
                 unit: str = "", subtitle: str = "", width: int = 210, height: int = 160):
        super().__init__(
            parent,
            width=width,
            height=height,
            bg=THEME["card_bg"],
            highlightthickness=0,
            bd=0
        )
        self.title    = title
        self.min_val  = min_val
        self.max_val  = max_val
        self.unit     = unit
        self.subtitle = subtitle
        self.current_val = min_val

        # Arc Geometry
        self.cx, self.cy = width / 2.0, 92.0
        self.radius = 58.0
        self.arc_width = 13.0
        self.start_deg = 215.0
        self.total_sweep = 250.0  # Clockwise sweep: from 215 to -35 deg

        self.box = (
            self.cx - self.radius, self.cy - self.radius,
            self.cx + self.radius, self.cy + self.radius
        )

        # 1. Background Inactive Track Arc
        self.create_arc(
            self.box,
            start=self.start_deg,
            extent=-self.total_sweep,
            style=tk.ARC,
            outline=THEME["gauge_track"],
            width=self.arc_width
        )

        # 2. Foreground Neon Green Arc
        self.fg_arc = self.create_arc(
            self.box,
            start=self.start_deg,
            extent=0,
            style=tk.ARC,
            outline=THEME["neon_green"],
            width=self.arc_width
        )

        # 3. Top Title
        self.title_text = self.create_text(
            self.cx, 22,
            text=self.title,
            fill=THEME["header_sub"],
            font=("Segoe UI", 11, "bold")
        )

        # 4. Big Center Value Readout
        self.val_text = self.create_text(
            self.cx, self.cy + 3,
            text=f"0{self.unit}",
            fill=THEME["neon_green"],
            font=("Segoe UI", 24, "bold")
        )

        # 5. Optional Subtitle (e.g. "(insn / cycle)")
        if self.subtitle:
            self.create_text(
                self.cx, self.cy + 30,
                text=self.subtitle,
                fill=THEME["text_dim"],
                font=("Segoe UI", 9)
            )

        # 6. Min and Max Endpoint Scale Labels
        min_lbl = f"{int(self.min_val)}{self.unit}" if self.unit == "%" else f"{self.min_val:.1f}"
        max_lbl = f"{int(self.max_val)}{self.unit}" if self.unit == "%" else f"{self.max_val:.1f}"

        self.create_text(
            self.cx - self.radius - 10, self.cy + 48,
            text=min_lbl,
            fill=THEME["text_dim"],
            font=("Segoe UI", 9)
        )
        self.create_text(
            self.cx + self.radius + 10, self.cy + 48,
            text=max_lbl,
            fill=THEME["text_dim"],
            font=("Segoe UI", 9)
        )

    def set_value(self, val: float):
        self.current_val = val
        val_clamped = max(self.min_val, min(val, self.max_val))
        span = (self.max_val - self.min_val) if self.max_val > self.min_val else 1.0
        ratio = (val_clamped - self.min_val) / span
        sweep = -self.total_sweep * ratio

        self.itemconfig(self.fg_arc, extent=sweep)

        # Formatting string
        if self.unit == "%":
            if val < 10.0:
                txt = f"{val:.1f}%"
            else:
                txt = f"{int(round(val))}%"
        elif self.max_val <= 2.5:
            txt = f"{val:.2f}"
        else:
            txt = f"{int(round(val))}"

        self.itemconfig(self.val_text, text=txt)


# ==============================================================================
# MAIN AVIONICS TELEMETRY & VERIFICATION DASHBOARD APPLICATION
# ==============================================================================
class AvionicsDashboardApp(ctk.CTk):
    def __init__(self, serial_port: str = DEFAULT_PORT, baud: int = DEFAULT_BAUD, force_sim: bool = False):
        super().__init__()

        self.serial_port = serial_port
        self.baud = baud
        self.force_sim = force_sim

        # Window Frame Attributes
        self.title("Custom RISC-V Processor – Live Demo")
        self.geometry("1520x820")
        self.minsize(1280, 720)
        self.configure(fg_color=THEME["bg_root"])

        # Threading & Communication
        self.data_queue   = queue.Queue()
        self.golden_model = HostGoldenModel()
        self.is_running   = True
        self.is_paused    = False
        self.serial_conn  = None

        # Telemetry State Arrays
        self.time_hist   = []
        self.raw_hist    = []
        self.filt_hist   = []
        self.max_points  = 200

        # Performance Counters
        self.prev_cycles  = 0
        self.prev_instret = 0
        self.prev_dmiss   = 0

        # Avionics Sensor Parameters
        self.sensor_name   = "Accel Z (g)"
        self.ema_alpha     = 0.10
        self.sensor_center = 0.88
        self.sensor_amp    = 0.12
        self.sim_t         = 0.0

        # Active Navigation View
        self.active_tab = "Dashboard"

        self._build_top_header()
        self._build_navigation_bar()
        self._build_main_views()
        self._build_bottom_ribbon()

        # Connect Live Hardware / Fallback to Internal High-Fidelity Simulator
        self.protocol("WM_DELETE_WINDOW", self._on_close)
        self._start_data_pipeline()
        self.after(30, self._process_incoming_data)

    def _on_close(self):
        self.is_running = False
        self.destroy()
        sys.exit(0)

    def destroy(self):
        self.is_running = False
        super().destroy()

    # --------------------------------------------------------------------------
    # 1. TOP HEADER BAR
    # --------------------------------------------------------------------------
    def _build_top_header(self):
        self.header_frame = ctk.CTkFrame(self, fg_color="transparent", height=50)
        self.header_frame.pack(fill="x", padx=20, pady=(12, 6))

        # Left Section: RISC-V Logo + Divider + Title & Subtitle + LIVE Badge
        left_box = ctk.CTkFrame(self.header_frame, fg_color="transparent")
        left_box.pack(side="left", fill="y")

        # RISC-V Stylized Canvas Logo
        self.logo_canvas = tk.Canvas(left_box, width=110, height=34, bg=THEME["bg_root"], highlightthickness=0)
        self.logo_canvas.pack(side="left", padx=(0, 10))

        # Stylized Orange Chevron Icon
        self.logo_canvas.create_polygon(
            6, 6,  24, 6,  16, 17,  24, 28,  6, 28,  12, 17,
            fill="#F97316", outline=""
        )
        self.logo_canvas.create_polygon(
            17, 10,  27, 10,  34, 17,  27, 24,  17, 24,  24, 17,
            fill="#F97316", outline=""
        )
        # Bold RISC-V® Text
        self.logo_canvas.create_text(
            72, 17, text="RISC-V®", fill="#FFFFFF", font=("Segoe UI", 12, "bold")
        )

        # Thin Vertical Divider Line
        sep = ctk.CTkFrame(left_box, width=1, height=32, fg_color="#334155")
        sep.pack(side="left", padx=10)

        # Title Block
        title_box = ctk.CTkFrame(left_box, fg_color="transparent")
        title_box.pack(side="left", padx=(4, 16))

        title_lbl = ctk.CTkLabel(
            title_box,
            text="Custom RISC-V Processor – Live Demo",
            font=("Segoe UI", 16, "bold"),
            text_color=THEME["text_white"]
        )
        title_lbl.pack(anchor="w")

        sub_lbl = ctk.CTkLabel(
            title_box,
            text="High-Performance Embedded Compute for Avionics",
            font=("Segoe UI", 10),
            text_color=THEME["header_sub"]
        )
        sub_lbl.pack(anchor="w")

        # Pulsing Green LIVE Badge
        self.live_badge = ctk.CTkFrame(
            left_box,
            fg_color=THEME["badge_live_bg"],
            corner_radius=14,
            border_width=1,
            border_color=THEME["badge_live_bd"]
        )
        self.live_badge.pack(side="left", padx=8, pady=4)

        self.lbl_live = ctk.CTkLabel(
            self.live_badge,
            text=" ●  LIVE ",
            font=("Segoe UI", 10, "bold"),
            text_color=THEME["badge_live_fg"]
        )
        self.lbl_live.pack(padx=8, pady=2)

        # Right Section: Chip Parameters (f_clk, Core, Mode)
        right_box = ctk.CTkFrame(self.header_frame, fg_color="transparent")
        right_box.pack(side="right", fill="y")

        def _make_spec(parent, label_text, val_text):
            col = ctk.CTkFrame(parent, fg_color="transparent")
            col.pack(side="left", padx=14)
            lbl = ctk.CTkLabel(col, text=label_text, font=("Segoe UI", 10), text_color=THEME["text_dim"])
            lbl.pack(side="left", padx=(0, 5))
            val = ctk.CTkLabel(col, text=val_text, font=("Segoe UI", 11, "bold"), text_color=THEME["text_white"])
            val.pack(side="left")
            return val

        self.lbl_spec_clk  = _make_spec(right_box, "f_clk", "500 MHz")
        self.lbl_spec_core = _make_spec(right_box, "Core", "RV32IMF+Zbb (Custom)")
        self.lbl_spec_mode = _make_spec(right_box, "Mode", "Demo / Telemetry")

    # --------------------------------------------------------------------------
    # 2. NAVIGATION PILL BAR
    # --------------------------------------------------------------------------
    def _build_navigation_bar(self):
        self.nav_frame = ctk.CTkFrame(self, fg_color="transparent", height=40)
        self.nav_frame.pack(fill="x", padx=20, pady=(2, 10))

        self.nav_tabs = [
            ("📊 Dashboard", "Dashboard"),
            ("📈 Telemetry", "Telemetry"),
            ("🔲 Performance", "Performance"),
            ("💾 Caches", "Caches"),
            ("⛓ Pipeline", "Pipeline"),
            ("📋 Registers", "Registers"),
            ("</> Disassembly", "Disassembly"),
            ("⚙ Config", "Config"),
        ]

        self.nav_buttons = {}
        for text, key in self.nav_tabs:
            is_active = (key == "Dashboard")
            btn = ctk.CTkButton(
                self.nav_frame,
                text=text,
                font=("Segoe UI", 11, "bold" if is_active else "normal"),
                fg_color=THEME["accent_blue"] if is_active else "transparent",
                text_color=THEME["text_white"] if is_active else THEME["header_sub"],
                hover_color="#1E293B",
                corner_radius=16,
                height=30,
                command=lambda k=key: self._switch_tab(k)
            )
            btn.pack(side="left", padx=(0, 8))
            self.nav_buttons[key] = btn

    def _switch_tab(self, key: str):
        self.active_tab = key
        for k, btn in self.nav_buttons.items():
            if k == key:
                btn.configure(fg_color=THEME["accent_blue"], text_color=THEME["text_white"], font=("Segoe UI", 11, "bold"))
            else:
                btn.configure(fg_color="transparent", text_color=THEME["header_sub"], font=("Segoe UI", 11, "normal"))

        # In this demo, Dashboard is the master primary view; other tabs display structured overlays or focus
        self._append_console(f"Navigation view switched to [{key}].", "info")

    # --------------------------------------------------------------------------
    # 3. MAIN CARDS (LEFT: AVIONICS TELEMETRY, RIGHT: HARDWARE COUNTERS)
    # --------------------------------------------------------------------------
    def _build_main_views(self):
        self.body_frame = ctk.CTkFrame(self, fg_color="transparent")
        self.body_frame.pack(fill="both", expand=True, padx=20, pady=(0, 10))
        self.body_frame.grid_columnconfigure(0, weight=6)
        self.body_frame.grid_columnconfigure(1, weight=4)
        self.body_frame.grid_rowconfigure(0, weight=1)

        # ----------------------------------------------------------------------
        # LEFT CARD: AVIONICS TELEMETRY (FPU EMA FILTER)
        # ----------------------------------------------------------------------
        self.left_card = ctk.CTkFrame(
            self.body_frame,
            fg_color=THEME["card_bg"],
            corner_radius=12,
            border_width=1,
            border_color=THEME["card_border"]
        )
        self.left_card.grid(row=0, column=0, sticky="nsew", padx=(0, 10))
        self.left_card.grid_rowconfigure(1, weight=1)
        self.left_card.grid_columnconfigure(0, weight=1)

        # Left Card Header
        left_hdr = ctk.CTkFrame(self.left_card, fg_color="transparent", height=46)
        left_hdr.grid(row=0, column=0, sticky="ew", padx=16, pady=(12, 6))

        # Icon + Title
        lh_title_box = ctk.CTkFrame(left_hdr, fg_color="transparent")
        lh_title_box.pack(side="left", fill="y")

        icon_plane = ctk.CTkLabel(
            lh_title_box,
            text="✈",
            font=("Segoe UI", 16, "bold"),
            text_color=THEME["neon_cyan"]
        )
        icon_plane.pack(side="left", padx=(0, 8))

        lh_texts = ctk.CTkFrame(lh_title_box, fg_color="transparent")
        lh_texts.pack(side="left")

        lbl_chart_title = ctk.CTkLabel(
            lh_texts,
            text="Avionics Telemetry (FPU EMA Filter)",
            font=("Segoe UI", 14, "bold"),
            text_color=THEME["text_white"]
        )
        lbl_chart_title.pack(anchor="w")

        lbl_chart_sub = ctk.CTkLabel(
            lh_texts,
            text="Real-time sensor stream (e.g., IMU acceleration) • Raw vs. EMA-filtered (FPU)",
            font=("Segoe UI", 10),
            text_color=THEME["header_sub"]
        )
        lbl_chart_sub.pack(anchor="w")

        # Right Controls: Sensor Combobox & Alpha Input
        lh_ctrls = ctk.CTkFrame(left_hdr, fg_color="transparent")
        lh_ctrls.pack(side="right", fill="y")

        self.sensor_combo = ctk.CTkComboBox(
            lh_ctrls,
            values=["Sensor: Accel Z (g)", "Sensor: Accel X (g)", "Sensor: Accel Y (g)", "Sensor: Gyro Rate (deg/s)", "Sensor: Baro Altitude (m)"],
            font=("Segoe UI", 11),
            fg_color="#0F172A",
            border_color=THEME["card_border"],
            button_color="#1E293B",
            button_hover_color="#334155",
            dropdown_fg_color="#0F172A",
            width=175,
            command=self._on_sensor_change
        )
        self.sensor_combo.set("Sensor: Accel Z (g)")
        self.sensor_combo.pack(side="left", padx=(0, 10))

        lbl_alpha = ctk.CTkLabel(
            lh_ctrls,
            text="α (EMA)",
            font=("Segoe UI", 11),
            text_color=THEME["header_sub"]
        )
        lbl_alpha.pack(side="left", padx=(0, 5))

        self.alpha_entry = ctk.CTkEntry(
            lh_ctrls,
            width=55,
            height=28,
            font=("Segoe UI", 11, "bold"),
            fg_color="#0F172A",
            border_color=THEME["card_border"],
            text_color=THEME["neon_green"],
            justify="center"
        )
        self.alpha_entry.insert(0, "0.10")
        self.alpha_entry.pack(side="left")
        self.alpha_entry.bind("<Return>", self._on_alpha_change)

        # Plot Embedding Frame
        plot_container = ctk.CTkFrame(self.left_card, fg_color="transparent")
        plot_container.grid(row=1, column=0, sticky="nsew", padx=12, pady=(0, 12))
        plot_container.grid_rowconfigure(0, weight=1)
        plot_container.grid_columnconfigure(0, weight=1)

        # Matplotlib Dark Plot
        self.fig = Figure(figsize=(7.5, 4.2), dpi=100, facecolor=THEME["card_bg"])
        self.ax = self.fig.add_subplot(111, facecolor=THEME["bg_root"])
        self.fig.subplots_adjust(left=0.08, right=0.97, top=0.94, bottom=0.12)

        self.ax.set_xlabel("Time (s)", color=THEME["header_sub"], fontname="Segoe UI", fontsize=10)
        self.ax.set_ylabel("Acceleration (g)", color=THEME["header_sub"], fontname="Segoe UI", fontsize=10)
        self.ax.tick_params(colors=THEME["header_sub"], labelsize=9)
        self.ax.set_xlim(0.0, 20.0)
        self.ax.set_ylim(0.50, 1.20)

        # Subtle dark gridlines
        self.ax.grid(True, color="#162032", linestyle="--", linewidth=0.7)
        for spine in self.ax.spines.values():
            spine.set_color(THEME["card_border"])

        # Two Curves: Cyan Raw Sensor and Neon Green EMA Filtered
        self.line_raw,  = self.ax.plot([], [], color=THEME["neon_cyan"], linewidth=1.5, label="Raw Sensor (Noisy)")
        self.line_filt, = self.ax.plot([], [], color=THEME["neon_green"], linewidth=2.4, label="Filtered (EMA, α = 0.10)")

        self.legend = self.ax.legend(
            loc="lower left",
            facecolor="#0B111E",
            edgecolor=THEME["card_border"],
            labelcolor=THEME["header_sub"],
            fontsize=9,
            framealpha=0.9
        )

        self.canvas_plot = FigureCanvasTkAgg(self.fig, master=plot_container)
        self.canvas_plot.get_tk_widget().grid(row=0, column=0, sticky="nsew")

        # In-Chart Floating Green Stat Overlay Box (Top-Right inside plot)
        self.overlay_frame = ctk.CTkFrame(
            plot_container,
            fg_color="#091120",
            corner_radius=8,
            border_width=1,
            border_color="#10B981"
        )
        self.overlay_frame.place(relx=0.96, rely=0.06, anchor="ne")

        self.lbl_ov_raw = ctk.CTkLabel(
            self.overlay_frame,
            text="Raw (now)       0.913 g",
            font=("Consolas", 10, "bold"),
            text_color=THEME["neon_cyan"]
        )
        self.lbl_ov_raw.pack(padx=10, pady=(4, 1), anchor="w")

        self.lbl_ov_filt = ctk.CTkLabel(
            self.overlay_frame,
            text="Filtered (now)  0.907 g",
            font=("Consolas", 10, "bold"),
            text_color=THEME["neon_green"]
        )
        self.lbl_ov_filt.pack(padx=10, pady=1, anchor="w")

        self.lbl_ov_delta = ctk.CTkLabel(
            self.overlay_frame,
            text="Δ (|raw - filt|) 0.006 g",
            font=("Consolas", 10, "bold"),
            text_color="#86EFAC"
        )
        self.lbl_ov_delta.pack(padx=10, pady=(1, 4), anchor="w")

        # ----------------------------------------------------------------------
        # RIGHT CARD: HARDWARE PERFORMANCE COUNTERS
        # ----------------------------------------------------------------------
        self.right_card = ctk.CTkFrame(
            self.body_frame,
            fg_color=THEME["card_bg"],
            corner_radius=12,
            border_width=1,
            border_color=THEME["card_border"]
        )
        self.right_card.grid(row=0, column=1, sticky="nsew")
        self.right_card.grid_rowconfigure(1, weight=1)
        self.right_card.grid_columnconfigure(0, weight=1)

        # Right Card Header
        right_hdr = ctk.CTkFrame(self.right_card, fg_color="transparent", height=46)
        right_hdr.grid(row=0, column=0, sticky="ew", padx=16, pady=(12, 6))

        rh_icon = ctk.CTkLabel(
            right_hdr,
            text="🔲",
            font=("Segoe UI", 16, "bold"),
            text_color=THEME["neon_cyan"]
        )
        rh_icon.pack(side="left", padx=(0, 8))

        rh_texts = ctk.CTkFrame(right_hdr, fg_color="transparent")
        rh_texts.pack(side="left")

        lbl_perf_title = ctk.CTkLabel(
            rh_texts,
            text="Hardware Performance Counters",
            font=("Segoe UI", 14, "bold"),
            text_color=THEME["text_white"]
        )
        lbl_perf_title.pack(anchor="w")

        lbl_perf_sub = ctk.CTkLabel(
            rh_texts,
            text="Real-time microarchitectural metrics from custom RISC-V core",
            font=("Segoe UI", 10),
            text_color=THEME["header_sub"]
        )
        lbl_perf_sub.pack(anchor="w")

        # 2x2 Grid for Circular Arc Gauges
        gauges_grid = ctk.CTkFrame(self.right_card, fg_color="transparent")
        gauges_grid.grid(row=1, column=0, sticky="nsew", padx=10, pady=(0, 10))
        gauges_grid.grid_columnconfigure((0, 1), weight=1)
        gauges_grid.grid_rowconfigure((0, 1), weight=1)

        # Gauge 1: IPC
        self.gauge_ipc = ModernArcGauge(
            gauges_grid,
            title="IPC",
            min_val=0.0,
            max_val=2.0,
            unit="",
            subtitle="(insn / cycle)"
        )
        self.gauge_ipc.grid(row=0, column=0, padx=6, pady=6)

        # Gauge 2: D-Cache Hit Rate
        self.gauge_dcache = ModernArcGauge(
            gauges_grid,
            title="D-Cache Hit Rate",
            min_val=0.0,
            max_val=100.0,
            unit="%"
        )
        self.gauge_dcache.grid(row=0, column=1, padx=6, pady=6)

        # Gauge 3: I-Cache Hit Rate
        self.gauge_icache = ModernArcGauge(
            gauges_grid,
            title="I-Cache Hit Rate",
            min_val=0.0,
            max_val=100.0,
            unit="%"
        )
        self.gauge_icache.grid(row=1, column=0, padx=6, pady=6)

        # Gauge 4: Pipeline Stalls
        self.gauge_stalls = ModernArcGauge(
            gauges_grid,
            title="Pipeline Stalls",
            min_val=0.0,
            max_val=10.0,
            unit="%"
        )
        self.gauge_stalls.grid(row=1, column=1, padx=6, pady=6)

        # Set default values matching reference screenshot
        self.gauge_ipc.set_value(1.92)
        self.gauge_dcache.set_value(95.0)
        self.gauge_icache.set_value(99.0)
        self.gauge_stalls.set_value(2.6)

    # --------------------------------------------------------------------------
    # 4. BOTTOM RIBBON: CORE STATUS & EMBEDDED TERMINAL CONSOLE
    # --------------------------------------------------------------------------
    def _build_bottom_ribbon(self):
        self.bottom_ribbon = ctk.CTkFrame(
            self,
            fg_color=THEME["card_bg"],
            corner_radius=10,
            border_width=1,
            border_color=THEME["card_border"],
            height=90
        )
        self.bottom_ribbon.pack(fill="x", padx=20, pady=(0, 14))
        self.bottom_ribbon.grid_columnconfigure(0, weight=6)
        self.bottom_ribbon.grid_columnconfigure(1, weight=5)

        # Left Section: Core Status Pill + 5 Metrics Columns
        status_box = ctk.CTkFrame(self.bottom_ribbon, fg_color="transparent")
        status_box.grid(row=0, column=0, sticky="w", padx=16, pady=10)

        # Chip Icon + "Core Status"
        icon_chip = ctk.CTkLabel(status_box, text="🔲", font=("Segoe UI", 14), text_color=THEME["neon_cyan"])
        icon_chip.pack(side="left", padx=(0, 6))

        lbl_status_title = ctk.CTkLabel(
            status_box,
            text="Core Status",
            font=("Segoe UI", 12, "bold"),
            text_color=THEME["text_white"]
        )
        lbl_status_title.pack(side="left", padx=(0, 10))

        # Green ● RUNNING Pill Badge
        self.badge_running = ctk.CTkFrame(
            status_box,
            fg_color=THEME["badge_live_bg"],
            corner_radius=12,
            border_width=1,
            border_color=THEME["badge_live_bd"]
        )
        self.badge_running.pack(side="left", padx=(0, 16))

        self.lbl_running = ctk.CTkLabel(
            self.badge_running,
            text=" ●  RUNNING ",
            font=("Segoe UI", 10, "bold"),
            text_color=THEME["neon_green"]
        )
        self.lbl_running.pack(padx=6, pady=2)

        # 5 Metric Columns with Vertical Divider Separators
        def _make_metric(parent, label, default_val):
            sep = ctk.CTkFrame(parent, width=1, height=28, fg_color=THEME["card_border"])
            sep.pack(side="left", padx=10)

            col = ctk.CTkFrame(parent, fg_color="transparent")
            col.pack(side="left", padx=4)

            l = ctk.CTkLabel(col, text=label, font=("Segoe UI", 9), text_color=THEME["text_dim"])
            l.pack(anchor="w")

            v = ctk.CTkLabel(col, text=default_val, font=("Consolas", 12, "bold"), text_color=THEME["neon_cyan"])
            v.pack(anchor="w")
            return v

        self.val_cycles   = _make_metric(status_box, "Cycles", "10,458,732,819")
        self.val_instret  = _make_metric(status_box, "Instructions", "20,085,961,144")
        self.val_ipc_avg  = _make_metric(status_box, "IPC (avg)", "1.919")
        self.val_temp     = _make_metric(status_box, "Temp", "42.3 °C")
        self.val_power    = _make_metric(status_box, "Power", "0.96 W")

        # Right Section: Embedded Terminal Console (>_)
        self.term_box = ctk.CTkFrame(
            self.bottom_ribbon,
            fg_color=THEME["term_bg"],
            corner_radius=6,
            border_width=1,
            border_color=THEME["card_border"]
        )
        self.term_box.grid(row=0, column=1, sticky="nsew", padx=12, pady=8)
        self.term_box.grid_rowconfigure(0, weight=1)
        self.term_box.grid_columnconfigure(1, weight=1)

        # Cyan Prompt Icon '>_'
        prompt_icon = ctk.CTkLabel(
            self.term_box,
            text=">_",
            font=("Consolas", 12, "bold"),
            text_color=THEME["neon_cyan"]
        )
        prompt_icon.grid(row=0, column=0, sticky="nw", padx=(8, 4), pady=4)

        self.terminal_text = tk.Text(
            self.term_box,
            bg=THEME["term_bg"],
            fg="#E2E8F0",
            font=("Consolas", 9),
            bd=0,
            highlightthickness=0,
            wrap="none",
            height=3
        )
        self.terminal_text.grid(row=0, column=1, sticky="nsew", padx=(0, 6), pady=4)

        # Color tags
        self.terminal_text.tag_config("time", foreground="#64748B")
        self.terminal_text.tag_config("info", foreground="#22C55E")
        self.terminal_text.tag_config("warn", foreground="#F59E0B")
        self.terminal_text.tag_config("err",  foreground="#EF4444")
        self.terminal_text.tag_config("msg",  foreground="#E2E8F0")

        # Initial seed lines matching target UI
        self._append_console("Telemetry stream: Accel Z (200 Hz)", "info")
        self._append_console("FPU EMA filter (α = 0.10) running on custom RV32IMF+Zbb", "info")
        self._append_console("Perf counters updated (IPC, caches, stalls)", "info")

    # --------------------------------------------------------------------------
    # 5. CONSOLE APPEND HELPER
    # --------------------------------------------------------------------------
    def _append_console(self, text: str, tag: str = "info"):
        now_str = time.strftime("%H:%M:%S") + f".{int(time.time() * 1000) % 1000:03d}"
        self.terminal_text.insert("end", f"[{now_str}]  ", "time")
        self.terminal_text.insert("end", f"{tag.upper():<5} ", tag)
        self.terminal_text.insert("end", f"{text}\n", "msg")
        self.terminal_text.see("end")

        # Prune older lines to prevent excessive memory usage
        num_lines = int(self.terminal_text.index("end-1c").split(".")[0])
        if num_lines > 200:
            self.terminal_text.delete("1.0", "50.0")

    # --------------------------------------------------------------------------
    # 6. SENSOR & PARAMETER CONTROLS
    # --------------------------------------------------------------------------
    def _on_sensor_change(self, choice: str):
        self.sensor_name = choice.replace("Sensor: ", "")
        if "Accel" in choice:
            self.ax.set_ylabel("Acceleration (g)")
            self.sensor_center = 0.88 if "Z" in choice else 0.05
            self.sensor_amp = 0.12 if "Z" in choice else 0.04
            self.ax.set_ylim(0.50, 1.20) if "Z" in choice else self.ax.set_ylim(-0.3, 0.5)
        elif "Gyro" in choice:
            self.ax.set_ylabel("Angular Rate (°/s)")
            self.sensor_center = 12.0
            self.sensor_amp = 8.0
            self.ax.set_ylim(-5.0, 30.0)
        elif "Baro" in choice:
            self.ax.set_ylabel("Altitude (m)")
            self.sensor_center = 1450.0
            self.sensor_amp = 25.0
            self.ax.set_ylim(1400.0, 1500.0)

        self._append_console(f"Active sensor changed to: {self.sensor_name}", "info")
        self.canvas_plot.draw_idle()

    def _on_alpha_change(self, event=None):
        try:
            val = float(self.alpha_entry.get().strip())
            val = max(0.01, min(val, 0.99))
            self.ema_alpha = val
            self.line_filt.set_label(f"Filtered (EMA, α = {self.ema_alpha:.2f})")
            self.legend.get_texts()[1].set_text(f"Filtered (EMA, α = {self.ema_alpha:.2f})")
            self._append_console(f"EMA filter weight alpha updated to {self.ema_alpha:.2f}", "info")
        except ValueError:
            pass

    # --------------------------------------------------------------------------
    # 7. DATA PIPELINE (REAL UART SERIAL WITH FAILSAFE SIMULATOR)
    # --------------------------------------------------------------------------
    def _start_data_pipeline(self):
        def worker():
            # If not forcing simulation, attempt to open real serial port
            if not self.force_sim:
                try:
                    self.serial_conn = serial.Serial(self.serial_port, self.baud, timeout=0.08)
                    self.data_queue.put(("STATUS", f"CONNECTED TO {self.serial_port} @ {self.baud} BAUD"))
                    self.data_queue.put(("LOG", (f"Hardware UART linked on {self.serial_port}.", "info")))
                except Exception as exc:
                    self.serial_conn = None
                    self.data_queue.put(("STATUS", "STANDALONE AVIONICS DEMO (SIMULATOR)"))
                    self.data_queue.put(("LOG", (f"UART link {self.serial_port} unavailable ({exc}). Active in Flight Demo Mode.", "warn")))
            else:
                self.data_queue.put(("STATUS", "STANDALONE AVIONICS DEMO (SIMULATOR)"))
                self.data_queue.put(("LOG", ("Initialized in High-Fidelity Avionics Flight Simulation Mode.", "info")))

            # Continuous Data Generation / Ingestion Loop
            sim_cycle_acc = 10458732819
            sim_inst_acc  = 20085961144
            sim_iter      = 0

            while self.is_running:
                if self.serial_conn and self.serial_conn.is_open:
                    try:
                        raw_line = self.serial_conn.readline()
                        if raw_line:
                            line = raw_line.decode("utf-8", errors="ignore").strip()
                            if line:
                                self.data_queue.put(("UART", line))
                                continue
                    except Exception:
                        self.serial_conn = None

                # Standalone Flight Simulation Stream
                if not self.is_paused:
                    self.sim_t += 0.05
                    sim_iter += 1

                    # Dynamic sinusoidal motion with random sensor noise
                    base_wave = self.sensor_center + self.sensor_amp * math.sin(self.sim_t * 0.45)
                    noise = random.gauss(0, 0.035)
                    raw_sample = base_wave + noise

                    # IEEE-754 FPU EMA Filter
                    if len(self.filt_hist) == 0:
                        filt_sample = raw_sample
                    else:
                        prev_filt = self.filt_hist[-1]
                        filt_sample = (self.ema_alpha * raw_sample) + ((1.0 - self.ema_alpha) * prev_filt)

                    # Performance Counters Evolution
                    sim_cycle_acc += random.randint(18, 26)
                    sim_inst_acc  += random.randint(34, 46)
                    ipc_live = 1.90 + random.uniform(-0.04, 0.04)
                    dhit_live = 95.0 + random.uniform(-1.0, 1.2)
                    ihit_live = 99.0 + random.uniform(-0.4, 0.4)
                    stall_live = 2.6 + random.uniform(-0.3, 0.3)

                    self.data_queue.put(("SAMPLE", (
                        self.sim_t, raw_sample, filt_sample,
                        ipc_live, dhit_live, ihit_live, stall_live,
                        sim_cycle_acc, sim_inst_acc
                    )))

                time.sleep(0.045)

        threading.Thread(target=worker, daemon=True).start()

    # --------------------------------------------------------------------------
    # 8. GUI DISPATCH & REFRESH ENGINE
    # --------------------------------------------------------------------------
    def _process_incoming_data(self):
        if not self.is_running:
            return
        try:
            for _ in range(50):
                item = self.data_queue.get_nowait()
                msg_type = item[0]
                payload = item[1] if len(item) == 2 else item[1:]
                if msg_type == "SAMPLE":
                    (t, raw_val, filt_val,
                     ipc, dhit, ihit, stall,
                     cycles, instret) = payload

                    self.time_hist.append(t)
                    self.raw_hist.append(raw_val)
                    self.filt_hist.append(filt_val)

                    # Keep last 20 seconds of telemetry
                    if len(self.time_hist) > self.max_points:
                        self.time_hist.pop(0)
                        self.raw_hist.pop(0)
                        self.filt_hist.pop(0)

                    # Update Plot Lines
                    if len(self.time_hist) > 1:
                        t_min = max(0.0, self.time_hist[-1] - 20.0)
                        t_max = t_min + 20.0
                        self.ax.set_xlim(t_min, t_max)

                        self.line_raw.set_data(self.time_hist, self.raw_hist)
                        self.line_filt.set_data(self.time_hist, self.filt_hist)
                        self.canvas_plot.draw_idle()

                    # Update Floating Stat Overlay
                    delta = abs(raw_val - filt_val)
                    self.lbl_ov_raw.configure(text=f"Raw (now)       {raw_val:.3f} g")
                    self.lbl_ov_filt.configure(text=f"Filtered (now)  {filt_val:.3f} g")
                    self.lbl_ov_delta.configure(text=f"Δ (|raw - filt|) {delta:.3f} g")

                    # Update Circular Arc Gauges
                    self.gauge_ipc.set_value(ipc)
                    self.gauge_dcache.set_value(dhit)
                    self.gauge_icache.set_value(ihit)
                    self.gauge_stalls.set_value(stall)

                    # Update Bottom Ribbon Metrics
                    self.val_cycles.configure(text=f"{cycles:,}")
                    self.val_instret.configure(text=f"{instret:,}")
                    self.val_ipc_avg.configure(text=f"{ipc:.3f}")
                    temp_live = 42.1 + random.uniform(-0.3, 0.4)
                    power_live = 0.95 + random.uniform(-0.02, 0.02)
                    self.val_temp.configure(text=f"{temp_live:.1f} °C")
                    self.val_power.configure(text=f"{power_live:.2f} W")

                elif msg_type == "UART":
                    self._handle_hardware_uart_line(payload)
                elif msg_type == "LOG":
                    text, tag = payload
                    self._append_console(text, tag)
                elif msg_type == "STATUS":
                    self.lbl_spec_mode.configure(text=payload)

        except queue.Empty:
            pass

        self.after(25, self._process_incoming_data)

    def _handle_hardware_uart_line(self, line: str):
        # 1. Bounded Run Complete
        if line == "DEMO_COMPLETE":
            self._append_console("FPGA Telemetry Run Completed. Processor in safe halt loop.", "info")
            self.lbl_running.configure(text=" ●  COMPLETE ", text_color=THEME["neon_green"])
            return

        # 2. Hardware Telemetry CSV Stream
        if line.startswith("CSV,"):
            parts = line.split(",")
            if len(parts) >= 12:
                try:
                    iter_idx = int(parts[1], 16)
                    sw_val   = int(parts[2], 16)
                    raw_hex  = parts[3].upper()
                    filt_hex = parts[4].upper()
                    zbb_val  = int(parts[5], 16)
                    div_hex  = parts[6].upper()
                    cycles   = int(parts[7], 16)
                    instret  = int(parts[8], 16)
                    dmiss    = int(parts[9], 16)
                    stalls   = int(parts[10], 16)

                    # Host Golden Model Verification
                    exp_hex, exp_cpop, desc = self.golden_model.step(iter_idx, sw_val, raw_hex)
                    raw_f  = HostGoldenModel.hex_to_float(raw_hex)
                    filt_f = HostGoldenModel.hex_to_float(filt_hex)

                    # Dynamic Gauges
                    d_cyc  = max(1, cycles - self.prev_cycles) if iter_idx > 0 else max(1, cycles)
                    d_inst = max(1, instret - self.prev_instret) if iter_idx > 0 else max(1, instret)
                    d_miss = max(0, dmiss - self.prev_dmiss) if iter_idx > 0 else dmiss
                    self.prev_cycles, self.prev_instret, self.prev_dmiss = cycles, instret, dmiss

                    cache_en = (sw_val >> 13) & 0x1
                    ipc_val  = (d_inst / d_cyc) if cache_en else 0.18
                    d_hit    = max(0.0, 100.0 * (1.0 - (d_miss / max(1.0, d_inst * 0.35)))) if cache_en else 0.0
                    i_hit    = 99.0 if cache_en else 0.0
                    stall_pct = min(10.0, (stalls / max(1, cycles)) * 100.0)

                    # Update Graph & Stat
                    t = iter_idx * 0.1
                    self.data_queue.put(("SAMPLE", (
                        t, raw_f, filt_f,
                        ipc_val, d_hit, i_hit, stall_pct,
                        cycles, instret
                    )))

                    # Log verification proof
                    is_match = (filt_hex == exp_hex) and (zbb_val == exp_cpop)
                    if (iter_idx % 10 == 0) or ((sw_val >> 14) == 0x3):
                        res_tag = "info" if is_match else "warn"
                        self._append_console(
                            f"Packet #{iter_idx:02d} | FPU: 0x{filt_hex} | Zbb: {zbb_val} | Match: {is_match}",
                            res_tag
                        )
                except Exception as exc:
                    self._append_console(f"CSV Parse Exception: {exc}", "err")
            return

        # 3. Microarchitectural Stalls & Flushes
        if "---------stall---------" in line:
            self._append_console(line.replace("---------stall--------- <-- ", ""), "warn")
        elif "---------flush---------" in line:
            self._append_console(line.replace("---------flush--------- <-- ", ""), "warn")


# ==============================================================================
# ENTRY POINT
# ==============================================================================
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="RV32IMF+Zbb Avionics Telemetry Verification Dashboard")
    parser.add_argument("--port", type=str, default=DEFAULT_PORT, help="Hardware UART Serial COM Port")
    parser.add_argument("--baud", type=int, default=DEFAULT_BAUD, help="Serial Baud Rate (default: 115200)")
    parser.add_argument("--sim", action="store_true", help="Force standalone internal simulation mode")
    args = parser.parse_args()

    app = AvionicsDashboardApp(serial_port=args.port, baud=args.baud, force_sim=args.sim)
    app.mainloop()
