# -*- coding: utf-8 -*-
"""
Created on Fri Jul 24 15:52:36 2026

@author: wei_jiarui&yukai

在“光伏实时预测APP”功能基础上
针对不同装机容量的光伏组件做可调整处理
"""

import sys
import tkinter as tk
from datetime import datetime
from pathlib import Path
from tkinter import messagebox, ttk
from pv_model_engine import load_model
APP_TITLE = "光伏实时功率预测"
MODEL_FILE_NAME = "pv_power_model.bin"

def application_directory():
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent

class PVRealtimeApp(tk.Tk):
    def __init__(self):
        tk.Tk.__init__(self)
        self.title(APP_TITLE)
        self.geometry("660x640")
        self.minsize(620, 600)
        self.model = None
        self.status_var = tk.StringVar(value="正在加载预测模型……")
        self.power_w_var = tk.StringVar(value="--")
        self.power_kw_var = tk.StringVar(value="--")
        self.time_var = tk.StringVar(value="尚未预测")
        self.irradiance_var = tk.StringVar()
        self.angle_var = tk.StringVar()
        self.temperature_var = tk.StringVar()
        self.wind_var = tk.StringVar()
        self.capacity_var = tk.StringVar()
        self._configure_style()
        self._build_ui()
        self.after(50, self._initialize_model)

    def _configure_style(self):
        style = ttk.Style(self)
        if "vista" in style.theme_names():
            style.theme_use("vista")
        elif "clam" in style.theme_names():
            style.theme_use("clam")
        style.configure("Title.TLabel", font=("Microsoft YaHei", 20, "bold"))
        style.configure("Hint.TLabel", font=("Microsoft YaHei", 10))
        style.configure("Input.TLabel", font=("Microsoft YaHei", 11))
        style.configure("Power.TLabel", font=("Microsoft YaHei", 30, "bold"))
        style.configure("Unit.TLabel", font=("Microsoft YaHei", 12))
        style.configure("Primary.TButton", font=("Microsoft YaHei", 12, "bold"))
        style.configure(
            "Section.TLabelframe.Label",
            font=("Microsoft YaHei", 11, "bold"),
        )

    def _build_ui(self):
        header = ttk.Frame(self, padding=(24, 20, 24, 10))
        header.pack(fill="x")
        ttk.Label(header, text=APP_TITLE, style="Title.TLabel").pack(anchor="center")
        ttk.Label(
            header,
            text="输入装机容量与环境参数，模型即时输出阵列总预测功率",
            style="Hint.TLabel",
        ).pack(anchor="center", pady=(6, 0))

        input_box = ttk.LabelFrame(
            self,
            text="实时输入",
            style="Section.TLabelframe",
            padding=18,
        )
        input_box.pack(fill="x", padx=24, pady=(8, 12))

        fields = [
            ("装机容量", self.capacity_var, "kWp", ">0，如1、5、10、50"),
            ("太阳直射辐照强度", self.irradiance_var, "W/m²", "0~1200"),
            ("太阳直射入射角", self.angle_var, "°", "0~90，相对于组件法线"),
            ("环境温度", self.temperature_var, "℃", "-30~35"),
            ("风速", self.wind_var, "m/s", "0~20"),
        ]
        for row, field in enumerate(fields):
            label, variable, unit, hint = field
            ttk.Label(input_box, text=label, style="Input.TLabel").grid(
                row=row, column=0, sticky="w", pady=8, padx=(0, 12)
            )
            entry = ttk.Entry(
                input_box,
                textvariable=variable,
                width=20,
                font=("Microsoft YaHei", 11),
            )
            entry.grid(row=row, column=1, sticky="ew", pady=8)
            ttk.Label(input_box, text=unit, width=7).grid(
                row=row, column=2, sticky="w", padx=(10, 4)
            )
            ttk.Label(input_box, text=hint, style="Hint.TLabel").grid(
                row=row, column=3, sticky="w"
            )
            if row == 0:
                entry.focus_set()

        input_box.columnconfigure(1, weight=1)

        button_frame = ttk.Frame(self, padding=(24, 0))
        button_frame.pack(fill="x")
        self.predict_button = ttk.Button(
            button_frame,
            text="立即预测",
            style="Primary.TButton",
            command=self.predict_power,
            state="disabled",
        )
        self.predict_button.pack(side="left", fill="x", expand=True, padx=(0, 6))
        ttk.Button(
            button_frame,
            text="清空输入",
            command=self.clear_inputs,
        ).pack(side="left", fill="x", expand=True, padx=(6, 0))

        result_box = ttk.LabelFrame(
            self,
            text="阵列总预测结果",
            style="Section.TLabelframe",
            padding=20,
        )
        result_box.pack(fill="both", expand=True, padx=24, pady=16)
        power_line = ttk.Frame(result_box)
        power_line.pack(pady=(10, 2))
        ttk.Label(
            power_line,
            textvariable=self.power_w_var,
            style="Power.TLabel",
        ).pack(side="left")
        ttk.Label(power_line, text=" W", style="Unit.TLabel").pack(
            side="left", padx=(4, 0), pady=(14, 0)
        )
        ttk.Label(
            result_box,
            textvariable=self.power_kw_var,
            font=("Microsoft YaHei", 13),
        ).pack(pady=(2, 8))
        ttk.Separator(result_box, orient="horizontal").pack(fill="x", pady=8)
        ttk.Label(result_box, textvariable=self.time_var, style="Hint.TLabel").pack()

        status_bar = ttk.Frame(self, padding=(14, 8))
        status_bar.pack(fill="x", side="bottom")
        ttk.Label(status_bar, textvariable=self.status_var).pack(side="left")
        self.bind("<Return>", lambda event: self.predict_power())

    def _initialize_model(self):
        model_path = application_directory() / MODEL_FILE_NAME
        try:
            self.model = load_model(model_path)
        except Exception as exc:
            self.status_var.set("模型加载失败")
            messagebox.showerror("无法启动预测", str(exc))
            return
        self.predict_button.configure(state="normal")
        self.status_var.set("模型已就绪，可输入装机容量进行预测")

    @staticmethod
    def _read_number(name, value):
        text = value.strip()
        if not text:
            raise ValueError("请填写%s。" % name)
        try:
            return float(text)
        except ValueError as exc:
            raise ValueError("%s必须填写数字。" % name) from exc

    def predict_power(self):
        if self.model is None:
            messagebox.showwarning("模型未就绪", "预测模型尚未成功加载。")
            return
        try:
            capacity_kWp = self._read_number("装机容量", self.capacity_var.get())
            if capacity_kWp <= 0:
                raise ValueError("装机容量必须大于0 kWp")
            irradiance = self._read_number("太阳直射辐照强度", self.irradiance_var.get())
            angle = self._read_number("太阳直射入射角", self.angle_var.get())
            temperature = self._read_number("环境温度", self.temperature_var.get())
            wind = self._read_number("风速", self.wind_var.get())

            power_1kwp = float(self.model.predict(irradiance, angle, temperature, wind))
            total_power_w = power_1kwp * capacity_kWp
        except Exception as exc:
            messagebox.showerror("输入或预测错误", str(exc))
            self.status_var.set("预测失败，请检查输入")
            return

        self.power_w_var.set("%.2f" % total_power_w)
        self.power_kw_var.set("%.4f kW" % (total_power_w / 1000.0))
        self.time_var.set("预测时间：%s" % datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
        self.status_var.set("预测完成，装机容量：%.2f kWp" % capacity_kWp)

    def clear_inputs(self):
        for variable in (
            self.capacity_var,
            self.irradiance_var,
            self.angle_var,
            self.temperature_var,
            self.wind_var,
        ):
            variable.set("")
        self.power_w_var.set("--")
        self.power_kw_var.set("--")
        self.time_var.set("尚未预测")
        self.status_var.set("输入已清空")

def main():
    app = PVRealtimeApp()
    app.mainloop()

if __name__ == "__main__":
    main()
