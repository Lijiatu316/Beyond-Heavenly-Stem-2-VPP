# -*- coding: utf-8 -*-
"""光伏物理模型运行引擎。

由光伏实时预测APP调用，最终用户无需运行本文件。
模型内部参数保存在 pv_power_model.bin 中。
"""

import hashlib
import json
import math
import struct
import zlib
from pathlib import Path


_MAGIC = b"PVPHYMODEL01"
_HEADER_FORMAT = ">12sI32s"
_HEADER_SIZE = struct.calcsize(_HEADER_FORMAT)


class PVModelError(Exception):
    pass


def _finite_number(name, value):
    try:
        number = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError("%s必须填写数字。" % name) from exc
    if not math.isfinite(number):
        raise ValueError("%s必须是有限数字。" % name)
    return number


class PVPhysicalModel(object):
    """从二进制模型文件加载参数并执行光伏物理预测。"""

    def __init__(self, params, metadata=None):
        self._p = dict(params)
        self.metadata = dict(metadata or {})

    def predict(self, irradiance, incidence_angle, ambient_temperature, wind_speed):
        g_input = _finite_number("太阳直射辐照强度", irradiance)
        angle = _finite_number("太阳直射入射角", incidence_angle)
        t_air = _finite_number("环境温度", ambient_temperature)
        wind = _finite_number("风速", wind_speed)

        if not 0.0 <= g_input <= 1200.0:
            raise ValueError("太阳直射辐照强度应在0~1200 W/m²范围内。")
        if not 0.0 <= angle <= 90.0:
            raise ValueError("太阳直射入射角应在0~90°范围内。")
        if not -30.0 <= t_air <= 35.0:
            raise ValueError("环境温度应在-30~35℃范围内。")
        if not 0.0 <= wind <= 20.0:
            raise ValueError("风速应在0~20 m/s范围内。")

        # 入射角定义：太阳光线与组件法线之间的夹角。
        angle_factor = max(0.0, math.cos(math.radians(angle)))
        effective_irradiance = g_input * angle_factor

        # 组件温度。
        t_cell = (
            t_air
            + self._p["k_board_temp"] * effective_irradiance
            - self._p["k_wind_cool"] * wind
        )
        t_cell = min(max(t_cell, t_air - 5.0), 80.0)

        # 温度修正。
        f_temp = 1.0 - self._p["alpha_temp"] * (
            t_cell - self._p["T_cell_std"]
        )
        f_temp = min(max(f_temp, 0.2), 1.1)

        # 基础功率。
        power = (
            effective_irradiance
            / self._p["G_std"]
            * self._p["Pn"]
            * self._p["eta_system"]
            * f_temp
        )

        # 弱光逆变器效率修正。
        if effective_irradiance < self._p["low_light_threshold"]:
            f_g = (
                self._p["low_light_base"]
                + effective_irradiance / self._p["low_light_divisor"]
            )
        else:
            f_g = 1.0
        power *= f_g

        # 功率限幅。
        max_power = self._p["Pn"] * self._p["max_power_ratio"]
        power = min(max(power, 0.0), max_power)
        return float(power)


def load_model(model_path):
    path = Path(model_path)
    if not path.exists():
        raise FileNotFoundError("未找到模型文件：%s" % path)

    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise PVModelError("无法读取模型文件：%s" % exc) from exc

    if len(raw) < _HEADER_SIZE:
        raise PVModelError("模型文件不完整。")

    magic, payload_length, digest = struct.unpack(
        _HEADER_FORMAT, raw[:_HEADER_SIZE]
    )
    if magic != _MAGIC:
        raise PVModelError("模型文件格式不正确。")

    payload = raw[_HEADER_SIZE:]
    if len(payload) != payload_length:
        raise PVModelError("模型文件长度校验失败。")
    if hashlib.sha256(payload).digest() != digest:
        raise PVModelError("模型文件完整性校验失败，文件可能已被修改。")

    try:
        model_data = json.loads(zlib.decompress(payload).decode("utf-8"))
    except Exception as exc:
        raise PVModelError("模型内容解析失败：%s" % exc) from exc

    params = model_data.get("parameters")
    if not isinstance(params, dict):
        raise PVModelError("模型缺少内部参数。")

    required = {
        "Pn",
        "eta_system",
        "G_std",
        "alpha_temp",
        "T_cell_std",
        "k_board_temp",
        "k_wind_cool",
        "low_light_threshold",
        "low_light_base",
        "low_light_divisor",
        "max_power_ratio",
    }
    if not required.issubset(params):
        raise PVModelError("模型内部参数不完整。")

    return PVPhysicalModel(params, model_data.get("metadata"))
