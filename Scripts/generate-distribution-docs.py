#!/usr/bin/env python3
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    KeepTogether,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


PROJECT_ROOT = Path(__file__).resolve().parent.parent
PDF_OUTPUT = PROJECT_ROOT / "output" / "pdf"
DMG_ASSETS = PROJECT_ROOT / "Distribution" / "DMG"
IMAGEGEN_BACKGROUND = PROJECT_ROOT / "Brand" / "Distribution" / "Installer-Background-ImageGen.png"
CHINESE_LIGHT = "/System/Library/Fonts/STHeiti Light.ttc"
CHINESE_MEDIUM = "/System/Library/Fonts/STHeiti Medium.ttc"
SF_FONT = "/System/Library/Fonts/SFNS.ttf"

INK = colors.HexColor("#202421")
SECONDARY = colors.HexColor("#606863")
GREEN = colors.HexColor("#2D8A62")
GREEN_SOFT = colors.HexColor("#E9F4EE")
ORANGE = colors.HexColor("#C9772E")
ORANGE_SOFT = colors.HexColor("#FFF2E5")
LINE = colors.HexColor("#D9DFDB")
PAPER = colors.HexColor("#F7F8F6")
WHITE = colors.white


def register_fonts() -> None:
    pdfmetrics.registerFont(TTFont("MDIChinese", CHINESE_LIGHT, subfontIndex=0))
    pdfmetrics.registerFont(TTFont("MDIChineseMedium", CHINESE_MEDIUM, subfontIndex=0))
    pdfmetrics.registerFont(TTFont("MDILatin", SF_FONT))


def paragraph_styles() -> dict[str, ParagraphStyle]:
    base = getSampleStyleSheet()
    return {
        "title": ParagraphStyle(
            "Title",
            parent=base["Title"],
            fontName="MDIChineseMedium",
            fontSize=25,
            leading=34,
            textColor=INK,
            alignment=TA_LEFT,
            spaceAfter=5 * mm,
            wordWrap="CJK",
        ),
        "subtitle": ParagraphStyle(
            "Subtitle",
            parent=base["BodyText"],
            fontName="MDIChinese",
            fontSize=11,
            leading=18,
            textColor=SECONDARY,
            spaceAfter=6 * mm,
            wordWrap="CJK",
        ),
        "heading": ParagraphStyle(
            "Heading",
            parent=base["Heading2"],
            fontName="MDIChineseMedium",
            fontSize=15,
            leading=22,
            textColor=INK,
            spaceBefore=4 * mm,
            spaceAfter=3 * mm,
            wordWrap="CJK",
        ),
        "body": ParagraphStyle(
            "Body",
            parent=base["BodyText"],
            fontName="MDIChinese",
            fontSize=10.5,
            leading=17,
            textColor=INK,
            spaceAfter=2.5 * mm,
            wordWrap="CJK",
        ),
        "small": ParagraphStyle(
            "Small",
            parent=base["BodyText"],
            fontName="MDIChinese",
            fontSize=8.7,
            leading=14,
            textColor=SECONDARY,
            wordWrap="CJK",
        ),
        "step_number": ParagraphStyle(
            "StepNumber",
            parent=base["BodyText"],
            fontName="MDILatin",
            fontSize=13,
            leading=17,
            textColor=WHITE,
            alignment=TA_CENTER,
        ),
        "step_title": ParagraphStyle(
            "StepTitle",
            parent=base["BodyText"],
            fontName="MDIChineseMedium",
            fontSize=11.5,
            leading=17,
            textColor=INK,
            wordWrap="CJK",
        ),
        "step_body": ParagraphStyle(
            "StepBody",
            parent=base["BodyText"],
            fontName="MDIChinese",
            fontSize=9.5,
            leading=15,
            textColor=SECONDARY,
            wordWrap="CJK",
        ),
        "center": ParagraphStyle(
            "Center",
            parent=base["BodyText"],
            fontName="MDIChinese",
            fontSize=10,
            leading=16,
            textColor=SECONDARY,
            alignment=TA_CENTER,
            wordWrap="CJK",
        ),
    }


def page_chrome(canvas, doc) -> None:
    width, height = A4
    canvas.saveState()
    canvas.setFillColor(PAPER)
    canvas.rect(0, 0, width, height, stroke=0, fill=1)
    canvas.setFillColor(GREEN)
    canvas.roundRect(18 * mm, height - 18 * mm, 7 * mm, 2.2 * mm, 1.1 * mm, stroke=0, fill=1)
    canvas.setStrokeColor(LINE)
    canvas.line(18 * mm, 16 * mm, width - 18 * mm, 16 * mm)
    canvas.setFont("MDIChinese", 7.5)
    canvas.setFillColor(SECONDARY)
    canvas.drawString(18 * mm, 10.5 * mm, "Mac 磁盘扫描助手 · 本机只读分析")
    canvas.drawRightString(width - 18 * mm, 10.5 * mm, f"{doc.page}")
    canvas.restoreState()


def card(content, background=WHITE, border=LINE, padding=5 * mm) -> Table:
    table = Table([[content]], colWidths=[162 * mm])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), background),
                ("BOX", (0, 0), (-1, -1), 0.7, border),
                ("LEFTPADDING", (0, 0), (-1, -1), padding),
                ("RIGHTPADDING", (0, 0), (-1, -1), padding),
                ("TOPPADDING", (0, 0), (-1, -1), padding),
                ("BOTTOMPADDING", (0, 0), (-1, -1), padding),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ]
        )
    )
    return table


def step(number: int, title: str, detail: str, styles) -> Table:
    number_cell = Table(
        [[Paragraph(str(number), styles["step_number"])]],
        colWidths=[9 * mm],
        rowHeights=[9 * mm],
    )
    number_cell.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), GREEN),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("BOX", (0, 0), (-1, -1), 0, GREEN),
            ]
        )
    )
    copy = [
        Paragraph(title, styles["step_title"]),
        Spacer(1, 0.7 * mm),
        Paragraph(detail, styles["step_body"]),
    ]
    table = Table([[number_cell, copy]], colWidths=[14 * mm, 146 * mm])
    table.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 1.5 * mm),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 2.8 * mm),
            ]
        )
    )
    return table


def bullet(text: str, styles) -> Table:
    dot = Paragraph("•", ParagraphStyle("Dot", parent=styles["body"], textColor=GREEN))
    table = Table([[dot, Paragraph(text, styles["body"])]], colWidths=[5 * mm, 155 * mm])
    table.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 0),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
            ]
        )
    )
    return table


def build_user_guide(styles) -> None:
    path = PDF_OUTPUT / "使用说明.pdf"
    doc = SimpleDocTemplate(
        str(path),
        pagesize=A4,
        leftMargin=24 * mm,
        rightMargin=24 * mm,
        topMargin=25 * mm,
        bottomMargin=23 * mm,
        title="Mac 磁盘扫描助手使用说明",
        author="Mac 磁盘扫描助手贡献者",
    )
    story = [
        Paragraph("Mac 磁盘扫描助手", styles["title"]),
        Paragraph(
            "看清空间去了哪里，再由你决定如何处理。App 默认只读，不删除、不移动、不上传文件。",
            styles["subtitle"],
        ),
        card(
            [
                Paragraph("开始前，你只需要记住一件事", styles["step_title"]),
                Spacer(1, 1.5 * mm),
                Paragraph(
                    "扫描结果是解释和建议，不是自动清理。对于微信聊天、照片、邮件、系统交换文件等高风险或系统管理数据，App 不会提供危险的直接删除操作。",
                    styles["body"],
                ),
            ],
            background=GREEN_SOFT,
            border=colors.HexColor("#B9D9C8"),
        ),
        Spacer(1, 6 * mm),
        Paragraph("三步完成第一次扫描", styles["heading"]),
        step(1, "安装并打开", "把 App 拖到“应用程序”文件夹，再从“应用程序”中打开。如果 macOS 阻止启动，请查看 DMG 中的《打不开？双击这里》。", styles),
        step(2, "选择合适的扫描范围", "第一次建议选择个人文件夹或已经怀疑较大的目录。全盘扫描可能包含数百万个项目，会更耗时。图片、音乐、邮件和其他 App 数据默认跳过，可在设置中逐项决定是否扫描。", styles),
        step(3, "阅读结果，再决定是否处理", "先看“磁盘概览”和“占用排行”，再打开具体项目查看来源、风险、判断可信度和建议动作。无法读取的范围会出现在“访问问题”中，不会被错误地计算为零。", styles),
        Spacer(1, 3 * mm),
        Paragraph("五个页面分别做什么", styles["heading"]),
        bullet("<b>磁盘概览：</b>查看容量、可用空间、扫描状态和已统计规模。", styles),
        bullet("<b>占用排行：</b>按大小、类型或风险查看目录与应用数据。", styles),
        bullet("<b>建议中心：</b>集中查看 Finder、目标 App 或固定安全模板提供的建议。", styles),
        bullet("<b>访问问题：</b>了解权限拒绝、受保护目录跳过和其他覆盖缺口。", styles),
        bullet("<b>使用说明：</b>随时回顾隐私边界、权限和扫描建议。", styles),
        PageBreak(),
        Paragraph("如何理解扫描结果", styles["title"]),
        Paragraph(
            "看清“它是什么、能否重建、由谁管理，以及误删后果”，比单看空间数字更重要。",
            styles["subtitle"],
        ),
        Paragraph("数据分类", styles["heading"]),
        card(
            [
                bullet("<b>可重新生成缓存：</b>通常风险较低，但仍建议优先使用对应 App 的清理入口。", styles),
                bullet("<b>应用内可管理数据：</b>例如浏览器模型或开发工具缓存，优先在目标 App 内处理。", styles),
                bullet("<b>用户数据：</b>聊天、文档、照片等，不应被当作普通缓存。", styles),
                bullet("<b>异常数据：</b>体积或数量明显异常，需要先确认来源和用途。", styles),
                bullet("<b>系统管理数据：</b>交换文件、系统目录等禁止手动删除。", styles),
                bullet("<b>未知或无权限：</b>App 会明确说明判断边界，不假装知道。", styles),
            ]
        ),
        Spacer(1, 5 * mm),
        Paragraph("为什么“预计可释放”可能不显示", styles["heading"]),
        Paragraph(
            "只有规则足够明确、风险足够低时才估算可释放空间。显示“暂不估算”并不代表占用为零，而是 App 不愿在证据不足时给出容易误导的数字。",
            styles["body"],
        ),
        Paragraph("扫描速度与硬盘影响", styles["heading"]),
        Paragraph(
            "扫描器主要读取目录结构、大小和日期，不打开文件内容。正常使用不会明显损伤 SSD；但全盘扫描会暂时占用 CPU、磁盘带宽和电量。优先扫描个人文件夹或可疑目录，通常更快、更安静。",
            styles["body"],
        ),
        Spacer(1, 5 * mm),
        Paragraph("隐私与安全边界", styles["heading"]),
        card(
            [
                bullet("所有分析都在本机完成，不上传路径、文件名或统计数据。", styles),
                bullet("不使用 sudo，不安装特权助手，不执行任意远程 Shell 字符串。", styles),
                bullet("不跟随符号链接，避免跨卷，并尽可能去重硬链接。", styles),
                bullet("系统管理数据和高风险用户数据只提供查看与说明。", styles),
            ],
            background=GREEN_SOFT,
            border=colors.HexColor("#B9D9C8"),
        ),
        Spacer(1, 7 * mm),
        Paragraph(
            "提示：如果你不确定某项数据能否处理，最安全的选择是“暂不处理”，先在 Finder 或来源 App 中核对。",
            styles["center"],
        ),
    ]
    doc.build(story, onFirstPage=page_chrome, onLaterPages=page_chrome)


def build_open_help(styles) -> None:
    path = PDF_OUTPUT / "打不开？双击这里.pdf"
    doc = SimpleDocTemplate(
        str(path),
        pagesize=A4,
        leftMargin=24 * mm,
        rightMargin=24 * mm,
        topMargin=25 * mm,
        bottomMargin=23 * mm,
        title="Mac 磁盘扫描助手打不开时的处理方法",
        author="Mac 磁盘扫描助手贡献者",
    )
    apple_url = "https://support.apple.com/zh-cn/102445"
    story = [
        Paragraph("打不开？先别担心", styles["title"]),
        Paragraph(
            "当前社区版本使用 ad-hoc 签名，尚未经过 Apple Developer ID 公证。即使文件完整，macOS 也可能在第一次打开时阻止启动。",
            styles["subtitle"],
        ),
        card(
            [
                Paragraph("先确认来源", styles["step_title"]),
                Spacer(1, 1.5 * mm),
                Paragraph(
                    "只有在你确认 DMG 来自项目官网或官方开源仓库，并且 SHA-256 与发布页面一致时，才继续覆盖安全提醒。如果来源不明，请删除文件，不要继续。",
                    styles["body"],
                ),
            ],
            background=ORANGE_SOFT,
            border=colors.HexColor("#E7C39F"),
        ),
        Spacer(1, 7 * mm),
        Paragraph("推荐处理步骤", styles["heading"]),
        step(1, "先完成安装", "把“Mac 磁盘扫描助手.app”拖到右侧 Applications 快捷方式。不要直接长期从 DMG 中运行。", styles),
        step(2, "尝试打开一次", "打开“应用程序”文件夹，连按“Mac 磁盘扫描助手”。即使出现阻止提示，也要先完成这一步，系统设置中的“仍要打开”选项才会出现。", styles),
        step(3, "打开隐私与安全性", "选择苹果菜单 > 系统设置 > 隐私与安全性，向下滚动到“安全性”。", styles),
        step(4, "选择“仍要打开”", "找到与 Mac 磁盘扫描助手有关的提示，点按“仍要打开”，再次确认“打开”；系统可能要求输入你的登录密码。", styles),
        Spacer(1, 3 * mm),
        card(
            [
                Paragraph("Apple 提示", styles["step_title"]),
                Spacer(1, 1.5 * mm),
                Paragraph(
                    "“仍要打开”通常只会在你尝试启动后的约一小时内出现。公司或学校管理的 Mac 可能禁止该操作，此时请联系管理员。",
                    styles["body"],
                ),
                Paragraph(
                    f'<link href="{apple_url}" color="#2D8A62"><u>查看 Apple 官方说明：在 Mac 上安全地打开 App</u></link>',
                    styles["body"],
                ),
                Spacer(1, 2 * mm),
                Paragraph(
                    "<b>请不要：</b>全局关闭 Gatekeeper、运行来源不明的脚本或终端命令，"
                    "也不要为了打开本 App 而授予 sudo、写入权限或不必要的完全磁盘访问权限。",
                    styles["small"],
                ),
            ],
            background=GREEN_SOFT,
            border=colors.HexColor("#B9D9C8"),
        ),
    ]
    doc.build(story, onFirstPage=page_chrome, onLaterPages=page_chrome)


def build_background() -> None:
    width, height = 1520, 960
    if not IMAGEGEN_BACKGROUND.is_file():
        raise FileNotFoundError(f"Missing ImageGen installer background: {IMAGEGEN_BACKGROUND}")

    source = Image.open(IMAGEGEN_BACKGROUND).convert("RGB")
    image = ImageOps.fit(
        source,
        (width, height),
        method=Image.Resampling.LANCZOS,
        centering=(0.5, 0.5),
    )

    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay, "RGBA")

    title_font = ImageFont.truetype(CHINESE_MEDIUM, 44, index=0)
    subtitle_font = ImageFont.truetype(CHINESE_LIGHT, 23, index=0)
    hint_font = ImageFont.truetype(CHINESE_LIGHT, 20, index=0)

    title = "拖到“应用程序”完成安装"
    title_box = draw.textbbox((0, 0), title, font=title_font)
    draw.text(
        ((width - (title_box[2] - title_box[0])) / 2, 156),
        title,
        font=title_font,
        fill=(32, 36, 33, 255),
    )
    subtitle = "只读分析 · 不上传 · 不修改文件"
    subtitle_box = draw.textbbox((0, 0), subtitle, font=subtitle_font)
    draw.text(
        ((width - (subtitle_box[2] - subtitle_box[0])) / 2, 218),
        subtitle,
        font=subtitle_font,
        fill=(91, 102, 95, 255),
    )

    arrow_y = 470
    arrow_start, arrow_end = 610, 910
    draw.line((arrow_start, arrow_y, arrow_end, arrow_y), fill=(45, 138, 98, 180), width=8)
    draw.line((arrow_end, arrow_y, arrow_end - 34, arrow_y - 26), fill=(45, 138, 98, 180), width=8)
    draw.line((arrow_end, arrow_y, arrow_end - 34, arrow_y + 26), fill=(45, 138, 98, 180), width=8)

    hint = "需要帮助？双击下方说明文档"
    hint_box = draw.textbbox((0, 0), hint, font=hint_font)
    draw.text(
        ((width - (hint_box[2] - hint_box[0])) / 2, 900),
        hint,
        font=hint_font,
        fill=(245, 242, 235, 235),
    )

    retina_image = Image.alpha_composite(image.convert("RGBA"), overlay).convert("RGB")
    standard_image = retina_image.resize((width // 2, height // 2), Image.Resampling.LANCZOS)
    standard_image.save(
        DMG_ASSETS / "background.png",
        "PNG",
        optimize=True,
        dpi=(72, 72),
    )
    retina_image.save(
        DMG_ASSETS / "background@2x.png",
        "PNG",
        optimize=True,
        dpi=(144, 144),
    )


def build_fallback_text() -> None:
    text = """Mac 磁盘扫描助手打不开时

当前社区版本尚未经过 Apple Developer ID 公证，因此 macOS 第一次打开时可能显示安全提醒。

1. 把“Mac 磁盘扫描助手.app”拖入“应用程序”。
2. 从“应用程序”中尝试打开一次。
3. 打开“系统设置”>“隐私与安全性”，向下滚动到“安全性”。
4. 找到对应提示并选择“仍要打开”，然后再次确认。

只有在你确认文件来自项目官网或官方开源仓库、且校验值一致时才继续。

不要全局关闭 Gatekeeper。
不要运行来源不明的脚本或终端命令。
不要授予 sudo、写入权限或不必要的完全磁盘访问权限。

Apple 官方说明：
https://support.apple.com/zh-cn/102445
"""
    (DMG_ASSETS / "打不开请看这里.txt").write_text(text, encoding="utf-8")


def main() -> None:
    PDF_OUTPUT.mkdir(parents=True, exist_ok=True)
    DMG_ASSETS.mkdir(parents=True, exist_ok=True)
    register_fonts()
    styles = paragraph_styles()
    build_user_guide(styles)
    build_open_help(styles)
    build_background()
    build_fallback_text()
    print(PDF_OUTPUT / "使用说明.pdf")
    print(PDF_OUTPUT / "打不开？双击这里.pdf")
    print(DMG_ASSETS / "background.png")
    print(DMG_ASSETS / "background@2x.png")
    print(DMG_ASSETS / "打不开请看这里.txt")


if __name__ == "__main__":
    main()
