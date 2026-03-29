# AMD XDNAアーキテクチャ概要

AMDのノートPC・デスクトップPC向けプロセッサに搭載されているAI専用チップ「XDNA」の技術解説ドキュメントです。  
設計思想・タイル構造・世代別の進化・ソフトウェアスタック・競合NPUとの比較・実際の利用シーンまでを1つの文書にまとめています。

## このリポジトリに含まれるもの

```
xdna-overview/
├── main.md        ← 本文（Markdown）
├── gen_pdf.py     ← Markdown → LaTeX → PDF 変換スクリプト
├── Makefile       ← ビルド用
└── build/         ← PDF等の出力先（git管理外）
```

- **`main.md`** を読めば内容はすべて確認できます。GitHub上でそのまま閲覧可能です。
- PDF版が必要な場合は、以下の手順でビルドできます。

## PDFのビルド方法

### 前提ツール

| ツール | 用途 | インストール例 |
|:--|:--|:--|
| [tectonic](https://tectonic-typesetting.github.io/) | LaTeX → PDF ビルド（必須） | `brew install tectonic` または `cargo install tectonic` |
| [mermaid-cli](https://github.com/mermaid-js/mermaid-cli) (mmdc) | 図表の画像化（任意） | `npm install -g @mermaid-js/mermaid-cli` |

> mermaid-cli がない場合、図表はテキスト（verbatim）としてPDFに出力されます。

### ビルド手順

```bash
make pdf
```

`build/main.pdf` が生成されます。PDFを開くには：

```bash
make miru    # macOS の open コマンドでPDFを表示
```

ビルド成果物を削除するには：

```bash
make clean
```

## main.md の主な内容

1. **概要** — XDNAとは何か、3行での要点
2. **技術的起源** — Xilinx AI Engineから AMD XDNAへの経緯
3. **アーキテクチャの基本構造** — 空間データフロー、2Dタイルアレイ、AIE計算タイルの内部
4. **世代別の進化** — XDNA → XDNA 2 → 今後のロードマップ、SKU一覧
5. **データ型と精度** — INT8/INT4/BFP16、GEMM性能の実測値
6. **ソフトウェアスタック** — ONNX Runtime、OGA、Lemonade SDK、Linuxドライバ
7. **競合NPUとの比較** — Intel NPU 4、Qualcomm Hexagonとの対比
8. **実際の利用シーン** — Copilot+ PC、ローカルLLM推論、エッジAI

## ライセンス・著者

文責: 濱田 剛（Tsuyoshi Hamada） — hamada@degima.ai
