# AMD XDNAアーキテクチャ概要

作成日時: 2026-03-28 15:31:57
更新日時: 2026-03-30 14:46:33

文責: 濱田 剛(Tsuyoshi Hamada)
Contact email: hamada@degima.ai

## 概要

AMD XDNAは、AMDのクライアントAPUに統合されたNPU（Neural Processing Unit）のマイクロアーキテクチャです。2022年にAMDが約350億ドルで買収したXilinxのVersal AI Engine技術を起源とし、機械学習やAI推論に特化した**空間データフロー（spatial dataflow）**アーキテクチャを採用しています。

従来のCPUやGPUが「キャッシュから繰り返しデータを取り出す」動的スケジューリング型であるのに対し、XDNAは**オンチップメモリとDMAによる決定論的なデータ移動**でAI演算を行います。これにより、CPUと比べて10〜40倍、GPUと比べて44%少ない消費電力で同等のAI推論を実現するとされています。

本稿では、XDNAの設計思想、タイル構造、世代別の進化、ソフトウェアスタック、競合NPUとの比較、実際の利用シーンまでを整理します。

## 3行で要点

- XDNAはXilinx Versal AI Engineを起源とする**空間データフロー型NPU**で、2D配列のAIEタイルが並列にデータを処理する。
- 世代ごとにタイル数・メモリ・データ型サポートが拡充され、XDNA（10 TOPS）→ XDNA 2（55 TOPS）→ 第3世代（10倍超）と急速に進化している。
- NPU上のLLM推論は**OnnxRuntime GenAI（OGA）**が担い、Copilot+ PC要件（40 TOPS以上）を満たすAI PC向けNPUの中核を担っている。

## 技術的起源：Xilinx AI Engineから AMD XDNAへ

XDNAを理解するには、その技術的なルーツを知ることが助けになります。

### Xilinx と FPGA の歴史

Xilinxは1984年創業のFPGAの発明者です。

| 年 | 出来事 |
|:--|:--|
| 1984 | Xilinx創業。世界初のファブレス半導体企業、FPGAを発明 |
| 1994 | Virtex FPGA発表 |
| 2012 | Zynq SoC発表（ARM + FPGA統合） |
| ~2014 | Xilinx、7nm Versal ACAP（コードネーム**Project Everest**）の開発を開始。10億ドル超・1,500名以上のエンジニアを投入 |
| 2016年3月 | 清華大学発のAIスタートアップ**DeePhi Technology（深鑑科技）**が設立 |
| 2018年7月 | XilinxがDeePhi Technologyを買収。DPU（Deep Processing Unit）IPとニューラルネットワーク圧縮技術を獲得 |
| 2018年 | Versal 7nmチップのテープアウト（37億トランジスタ） |
| 2019 | Versal ACAP発表（プロセッサコア + プログラマブルロジック + **AI Engine**） |
| 2020年10月 | AMDがXilinx買収を発表 |
| 2022年2月 | AMD、Xilinx買収完了（約350億ドル、全株式交換） |
| 2023年4月 | **AMD XDNA**として初代をRyzen 7040に搭載 |

### Versal AI Engine → XDNA

Xilinxが2019年に発表したVersal ACAPには「AI Engine（AIE）」と呼ばれるタイル型の演算アレイが搭載されていました。このAIEは、FPGAロジックに隣接する空間データフローエンジンとして、5G通信やレーダー信号処理向けに設計されたものです。

AMD XDNAは、このAIEをクライアントAPU向けに再設計・最適化した技術です。データセンター向けのVersal AIEと共通の設計思想（タイル配列、VLIW+SIMD、DMAベースのデータ移動）を持ちながら、低消費電力のノートPC・エッジデバイス向けにチューニングされています。

### 補足：DeePhi Technology（深鑑科技）との関係

XDNAの技術的ルーツを辿るうえで、XilinxによるDeePhi Technology（深鑑科技）の買収も重要なトピックです。両者には深い関わりがありますが、技術的な系譜としては区別して理解するとよりクリアになります。

**DeePhi Technology**は2016年に清華大学の卒業生（姚頌、汪玉、韓松、単羿）によって設立されたAIチップスタートアップで、FPGA上でニューラルネットワーク推論を効率化するDPU（Deep Processing Unit）ソフトIPと、ニューラルネットワークの枝刈り・圧縮技術（Deep Compression）を開発していました。Xilinxは2017年からDeephiに出資し、2018年7月に買収しています。

しかし、XDNAの直接の祖先であるVersal AI Engineは、Xilinx社内でIvo Bolsens（CTO）率いるチームが設計したものです。Versalの開発プロジェクト（Project Everest）は**2014年頃に開始**されており、DeePhi設立（2016年）の約2年前です。10億ドル超の投資と1,500名以上のエンジニアが投入された大規模プロジェクトでした（[VentureBeat, 2018](https://venturebeat.com/business/xilinx-spent-1-billion-over-4-years-to-make-adaptable-computing-chip/)）。

両者の技術的な関係は以下のとおりです。

| | Versal AI Engine → XDNA | DeePhi DPU → Vitis AI |
|:--|:--|:--|
| 技術レベル | シリコン（ハードウェア） | ソフトIP / オーバーレイ |
| 本質 | 硬化されたVLIWベクトルプロセッサタイルの2Dアレイ | FPGA / AI Engineリソース上で動作するDNN推論IPコア |
| 関係 | DPUが動作する**基盤** | AI Engineの**上で**動作するソフトウェア層 |

DeePhi技術は買収後、Xilinx（現AMD）の**Vitis AIフレームワーク**に統合され、DPU IPやモデル最適化ツール（枝刈り・量子化）としてAI Engineハードウェアの上で活用されています。XDNAのハードウェアアーキテクチャとDeePhi由来のソフトウェア技術は、それぞれ独立した起源を持ちながら「基盤と応用」として組み合わさることで、現在のAMD AIプラットフォームを形づくっています。

## XDNAアーキテクチャの基本構造

### 空間データフロー（spatial dataflow）とは

一般的なCPU/GPUは、演算器が必要なデータをキャッシュ階層（L1→L2→L3→DRAM）から**動的に**フェッチします。この動的スケジューリングはフレキシブルですが、キャッシュミス時の待ち時間やフェッチ自体のエネルギーコストが発生します。

XDNAの空間データフローアーキテクチャでは、考え方が根本的に異なります。

```mermaid
graph LR
    subgraph CPU_GPU["CPU / GPU（動的スケジューリング型）"]
        direction LR
        A1[演算器] -->|"要求時フェッチ"| B1[L1$]
        B1 -->|"ミス"| C1[L2$]
        C1 -->|"ミス"| D1[L3$]
        D1 -->|"ミス"| E1[DRAM]
    end
```

```mermaid
graph LR
    subgraph XDNA["XDNA（空間データフロー型）"]
        direction LR
        A2[DMA] -->|"事前スケジュール済"| B2[メモリタイル]
        B2 -->|"ローカル転送"| C2[計算タイル]
        C2 --> D2[計算タイル]
        D2 --> E2["..."]
    end
```

データの移動経路とタイミングがコンパイル時に決まるため、実行中のキャッシュミスという概念がなく、消費電力を大幅に抑えられます。

### シストリックアレイとの違い

2Dに並んだ演算要素間をデータが流れるという外見上の類似から、XDNAはシストリックアレイ（Google TPU等で採用）と混同されやすいですが、両者は設計思想が異なります。

| 特性 | シストリックアレイ（TPU等） | AMD XDNA AIEタイルアレイ |
|:--|:--|:--|
| 処理要素の性質 | 固定機能PE（MAC演算等にハードワイヤード） | **プログラマブルプロセッサ**（VLIW+SIMD＋スカラRISC、各タイルに命令メモリ） |
| データフロー | ハードウェアトポロジで決まる一定リズムの波状伝搬 | **プログラマブルDMAとインターコネクト**でソフトウェア制御 |
| 各要素の独立性 | 全PEが同一演算を実行 | 各タイルが**異なるプログラムを独立実行**可能 |
| 並列性の種類 | 主にデータ並列（行列演算に特化） | 空間並列・タスク/パイプライン並列・命令レベル並列を選択可能 |
| 柔軟性 | 特定演算パターン（GEMM、畳み込み）に最適化、それ以外は不得手 | CGRA（粗粒度再構成可能アーキテクチャ）として多様なワークロードに対応 |
| 再構成 | 不可（ハードウェア固定） | ファームウェア更新でタイルの役割やデータフローを変更可能 |

XDNAのAIEタイルアレイは、シストリックアレイ的なデータフローパターンを並列性の選択肢の**一つとして実装できる**、より汎用的なアーキテクチャです。Xilinxのホワイトペーパー[WP506: Xilinx AI Engines and Their Applications](https://spiritelectronics.com/pdf/wp506-ai-engine.pdf)では、AIEの並列性として命令レベル並列（6-way VLIW）とデータレベル並列（512bit SIMD）を明記し、さらにタイル間の通信としてカスケードインターフェース（隣接タイルへの部分結果の直接転送）をサポートすると記載しています。このカスケードインターフェースにより、シストリックアレイ的な波状データ伝搬パターンを実装できますが、それは各タイルのプログラマブルなDMA・AXI-Streamインターコネクトが提供する柔軟なデータ移動の一形態です。AIEアーキテクチャの詳細は[AM009: Versal AI Engine Architecture Manual](https://docs.amd.com/r/en-US/am009-versal-ai-engine/AI-Engine-Array-Overview)も参照してください。

### 2Dタイルアレイ

XDNAの心臓部は「2Dタイルアレイ」です。計算タイル（Compute Tile）とメモリタイル（Memory Tile）がグリッド状に配置されています。

```mermaid
graph TD
    subgraph ARRAY["XDNA 2Dタイルアレイ（Strix Point: 4行×8列 = 32計算タイル）"]
        direction TB
        subgraph R3["行3: 計算タイル ×8"]
            direction LR
            C30[計算] ~~~ C31[計算] ~~~ C32[計算] ~~~ C33["... ×8"]
        end
        subgraph R2["行2: 計算タイル ×8"]
            direction LR
            C20[計算] ~~~ C21[計算] ~~~ C22[計算] ~~~ C23["... ×8"]
        end
        subgraph R1["行1: 計算タイル ×8"]
            direction LR
            C10[計算] ~~~ C11[計算] ~~~ C12[計算] ~~~ C13["... ×8"]
        end
        subgraph R0["行0: 計算タイル ×8"]
            direction LR
            C00[計算] ~~~ C01[計算] ~~~ C02[計算] ~~~ C03["... ×8"]
        end
        subgraph MR["メモリ行: メモリタイル（L2） ×8"]
            direction LR
            M0[Mem] ~~~ M1[Mem] ~~~ M2[Mem] ~~~ M3["... ×8"]
        end
    end
    R3 --- R2 --- R1 --- R0 --- MR
    MR <-->|"DMA ×8列"| DDR[(DDR メインメモリ)]
```

- **計算タイル（Compute Tile）**: 各行の要素。AI演算を実行する
- **メモリタイル（Memory Tile）**: 各列の最下行。L2キャッシュとして機能し、DDRとの間のデータステージングを担う
- **DMAエンジン**: 各列に専用のDMAが配置され、ホストDDRとメモリタイル間のデータ転送を担当

### AIE計算タイルの内部構造

各計算タイルは、小さな独立したプロセッサのような構造を持っています。

```mermaid
graph TD
    subgraph TILE["AIE計算タイル"]
        VP["ベクトルプロセッサ<br/>VLIW + SIMD<br/>テンソル演算に最適化<br/>1.3 GHz以上"]
        SP["スカラプロセッサ<br/>RISC<br/>制御フロー・補助"]
        PM["プログラムメモリ<br/>命令格納"]
        DM["ローカルデータメモリ<br/>重み・活性化値"]
        IC["インターコネクト<br/>タイル間通信"]
    end
    SP --> VP
    PM --> VP
    DM --> VP
    IC <--> DM
    IC <--> VP
```

| 構成要素 | 役割 |
|:--|:--|
| ベクトルプロセッサ（VLIW + SIMD） | 行列積・畳み込みなどのテンソル演算を並列実行。1.3 GHz以上で動作 |
| スカラプロセッサ（RISC） | 制御フロー、アドレス計算、補助的な処理を担当 |
| プログラムメモリ | タイルが実行する命令を格納 |
| ローカルデータメモリ | 重み、活性化値、係数などを格納。外部DRAMへのアクセスを最小化 |
| プログラマブルインターコネクト | 隣接タイルとの高帯域・低遅延なデータ通信を提供 |

「タイル1つが小さな専用プロセッサ」であり、このタイルが数十個並んで協調動作するのがXDNAの本質です。

### 行列積（GEMM）の実行イメージ

NPUの最も重要なワークロードは行列積（General Matrix Multiplication, GEMM）です。XDNAでのGEMM実行は概ね以下のように進みます。

1. **タイリング**: 大きな行列を小さなブロック（タイル）に分割
2. **DMA転送**: DMAエンジンがDDRからメモリタイル経由で各計算タイルにブロックを配送
3. **計算**: 各計算タイルのベクトルプロセッサがFMA（積和演算）を実行
4. **蓄積**: 部分積を計算タイル間で受け渡しながら蓄積
5. **書き戻し**: 結果をDMA経由でDDRに返却

行列が複数の計算タイルに分散されて並列に処理されるため、タイル数が増えるほどスループットが向上します。

## 世代別の進化

### 仕様比較

| 項目 | XDNA（初代） | XDNA（Hawk Point） | XDNA 2 |
|:--|:--|:--|:--|
| 登場時期 | 2023年4月 | 2024年 | 2024年 |
| 搭載プロセッサ | Ryzen 7040 (Phoenix) | Ryzen 8040 (Hawk Point) | Ryzen AI 300 (Strix Point) |
| CPUアーキテクチャ | Zen 4 | Zen 4 | Zen 5 |
| タイルトポロジ | 4行 × 5列 | 4行 × 5列 | 4行 × 8列 |
| 計算タイル数 | 20 | 20 | 32 |
| L2メモリ合計 | 2,560 KB | 2,560 KB | 4,096 KB |
| ピーク性能（INT8） | 10 TOPS | 16 TOPS | 55 TOPS |
| BFP16対応 | なし | なし | あり |
| 主な改善点 | — | ファームウェア最適化・クロック向上 | タイル数増、メモリ60%増、BFP16対応、5倍の性能 |

### 初代 XDNA（Phoenix / Hawk Point）

2023年にRyzen 7040シリーズとして登場。AMD初のクライアント向けNPUで、4×5のタイル配列により最大10 TOPSを実現しました。Windows上のAI推論タスクの省電力オフロードが主な用途です。

Hawk Pointはハードウェア的にはPhoenixとほぼ同一ですが、ファームウェア更新とクロック最適化により16 TOPSに向上しました。

### XDNA 2（Strix Point）

2024年にRyzen AI 300シリーズとして登場した第2世代は、大幅な強化が入りました。

- **タイル数**: 20 → 32（60%増）
- **L2メモリ**: 2,560 KB → 4,096 KB（60%増）
- **BFP16（Block Floating Point 16）**: ブロック単位で指数を共有し、INT8に近いメモリ効率でFP16に近い精度を実現する新データ型
- **性能**: 初代比で最大5倍、55 TOPSに到達

XDNA 2はMicrosoftのCopilot+ PC要件（40 TOPS以上）を十分に満たし、ローカルLLM推論の実用的な基盤として位置づけられています。

### 今後のロードマップ

AMDが公開しているロードマップでは、以下の世代が予告されています。

| コードネーム | 時期 | NPU世代 | 備考 |
|:--|:--|:--|:--|
| Gorgon Point | 2026年 | XDNA 2（継続） | Zen 5リフレッシュ |
| Medusa Point | 2027年 | 第3世代XDNA | 現行比10倍以上のAI推論性能 |

第3世代では10倍以上の性能向上が予告されており、オンデバイスでのLLM推論がさらに実用的になることが期待されます。

### XDNA搭載プロセッサ SKU一覧

#### 初代 XDNA — Ryzen 7040シリーズ（Phoenix, 2023年）

対応メモリ: DDR5-5600 / LPDDR5X-7500。プロセスノード: TSMC 4nm。CPU: Zen 4、GPU: RDNA 3。

| SKU | コア/スレッド | ブースト | iGPU | NPU (TOPS) | TDP | 市販PC例 |
|:--|:--|:--|:--|:--|:--|:--|
| Ryzen 9 7940HS | 8C/16T | 5.2 GHz | Radeon 780M (12CU) | 10 | 35–54W | ASUS ROG Zephyrus G14 (2023) |
| Ryzen 7 7840HS | 8C/16T | 5.1 GHz | Radeon 780M (12CU) | 10 | 35–54W | Framework Laptop 16 |
| Ryzen 5 7640HS | 6C/12T | 5.0 GHz | Radeon 760M (8CU) | 10 | 35–54W | — |
| Ryzen 7 7840U | 8C/16T | 5.1 GHz | Radeon 780M (12CU) | 10 | 15–30W | Lenovo ThinkPad T14s Gen 4 |
| Ryzen 5 7640U | 6C/12T | 4.9 GHz | Radeon 760M (8CU) | 10 | 15–30W | — |

Ryzen 5 7540U、Ryzen 5 7545U、Ryzen 3 7440U は XDNA NPU を搭載していない。7540U / 7440U は AMD 脚注 GD-220d で明示的に Ryzen AI 対象外とされている。7545U は GD-220d の除外リストにないものの、137mm² の Phoenix 2 ダイ（XDNA IP ブロックを物理的に含まない）を使用しており、製品ページにも AI 仕様の記載がない。

PRO版（法人向け）: Ryzen 7 PRO 7840U、Ryzen 5 PRO 7640U など。Lenovo ThinkPad X13 Gen 4、ThinkPad P14s Gen 4 等で採用。

#### 初代 XDNA（リフレッシュ）— Ryzen 8040シリーズ（Hawk Point, 2024年）

対応メモリ: DDR5-5600 / LPDDR5X-7500。プロセスノード: TSMC 4nm。CPU: Zen 4、GPU: RDNA 3。ファームウェア最適化によりNPU性能が16 TOPSに向上。

| SKU | コア/スレッド | ブースト | iGPU | NPU (TOPS) | TDP | 市販PC例 |
|:--|:--|:--|:--|:--|:--|:--|
| Ryzen 9 8945HS | 8C/16T | 5.2 GHz | Radeon 780M (12CU) | 16 | 35–54W | — |
| Ryzen 7 8845HS | 8C/16T | 5.1 GHz | Radeon 780M (12CU) | 16 | 35–54W | HP OMEN 17 (2024) |
| Ryzen 7 8840HS | 8C/16T | 5.1 GHz | Radeon 780M (12CU) | 16 | 20–30W | — |
| Ryzen 7 8840U | 8C/16T | 5.1 GHz | Radeon 780M (12CU) | 16 | 15–30W | Lenovo ThinkPad T14 Gen 5 |
| Ryzen 5 8645HS | 6C/12T | 5.0 GHz | Radeon 760M (8CU) | 16 | 35–54W | — |
| Ryzen 5 8640HS | 6C/12T | 4.9 GHz | Radeon 760M (8CU) | 16 | 20–30W | — |
| Ryzen 5 8640U | 6C/12T | 4.9 GHz | Radeon 760M (8CU) | 16 | 15–30W | Acer Swift Go 14 (2024) |
| Ryzen 5 8540U | 6C/12T | 4.9 GHz | Radeon 740M (4CU) | **なし** | 15–30W | — |
| Ryzen 3 8440U | 4C/8T | 4.7 GHz | Radeon 740M (4CU) | **なし** | 15–30W | — |

Ryzen 5 8540U と Ryzen 3 8440U はXDNA NPUを**搭載していません**。PRO版（Ryzen 7 PRO 8840U 等）も法人向けに提供。

#### XDNA 2 — Ryzen AI 300シリーズ（Strix Point / Krackan Point, 2024–2025年）

対応メモリ: DDR5-5600 / LPDDR5X-7500。プロセスノード: TSMC 4nm。CPU: Zen 5 + Zen 5c（ハイブリッド）、GPU: RDNA 3.5。Copilot+ PC対応（40 TOPS以上）。

**Strix Point（上位）**:

| SKU | コア/スレッド | ブースト | iGPU | NPU (TOPS) | TDP | 市販PC例 |
|:--|:--|:--|:--|:--|:--|:--|
| Ryzen AI 9 HX 375 | 12C/24T | 5.1 GHz | Radeon 890M (16CU) | 55 | 15–54W | — |
| Ryzen AI 9 HX 370 | 12C/24T | 5.1 GHz | Radeon 890M (16CU) | 50 | 15–54W | ASUS ROG Zephyrus G16 (2024) |
| Ryzen AI 9 365 | 10C/20T | 5.0 GHz | Radeon 880M (12CU) | 50 | 15–54W | ASUS Zenbook S 16 (UM5606) |
| Ryzen AI 7 PRO 360 | 8C/16T | 5.0 GHz | Radeon 880M (12CU) | 50 | 15–54W | — |

**Krackan Point（普及帯）**:

| SKU | コア/スレッド | ブースト | iGPU | NPU (TOPS) | TDP | 市販PC例 |
|:--|:--|:--|:--|:--|:--|:--|
| Ryzen AI 7 350 | 8C/16T | 5.0 GHz | Radeon 860M (8CU) | 50 | 15–54W | ASUS Zenbook S 16 (UM5606KA)、Dell 16 Plus |
| Ryzen AI 5 340 | 6C/12T | 4.8 GHz | Radeon 840M (4CU) | 50 | 15–54W | Dell 14 Plus、Lenovo IdeaPad Slim 5 |

PRO版: Ryzen AI 7 PRO 350、Ryzen AI 5 PRO 340（法人向け）。

#### XDNA 2 — Ryzen AI Maxシリーズ（2025年）

対応メモリ: 256-bit LPDDR5X-8000（最大128GB、うち最大96GBをVRAMに転用可能な統合メモリ構成）。プロセスノード: TSMC 4nm。CPU: Zen 5（全コア、ハイブリッドなし）、GPU: RDNA 3.5。ソケット: FP11。コードネーム: Strix Halo。大容量メモリにより、100B超パラメータのLLMもローカル実行が可能。

| SKU | コア/スレッド | ブースト | iGPU | NPU (TOPS) | cTDP | 市販PC例 |
|:--|:--|:--|:--|:--|:--|:--|
| Ryzen AI Max+ 395 | 16C/32T | 5.1 GHz | Radeon 8060S (40CU) | 50 | 45–120W | — |
| Ryzen AI Max+ 392 | 12C/24T | 5.0 GHz | Radeon 8060S (40CU) | 50 | 45–120W | — |
| Ryzen AI Max+ 388 | 8C/16T | 5.0 GHz | Radeon 8060S (40CU) | 50 | 45–120W | — |
| Ryzen AI Max 390 | 12C/24T | 5.0 GHz | Radeon 8050S (32CU) | 50 | 45–120W | ASUS ROG Flow Z13 (2025) |
| Ryzen AI Max 385 | 8C/16T | 5.0 GHz | Radeon 8050S (32CU) | 50 | 45–120W | — |

PRO版: Ryzen AI Max+ PRO 395、Max PRO 390、Max PRO 385、Max PRO 380（法人・モバイルワークステーション向け）。PRO 380 はPRO専用で、Radeon 8040S（16CU）/ 最大64GBメモリの縮小構成。

#### XDNA 2 — Ryzen AI 400シリーズ（ラップトップ, 2026年）

対応メモリ: DDR5-5600 / LPDDR5X-8000〜8533。プロセスノード: TSMC 4nm。CPU: Zen 5 + Zen 5c（ハイブリッド）、GPU: RDNA 3.5。コードネーム: Gorgon Point。

| SKU | コア/スレッド | ブースト | iGPU | NPU (TOPS) | cTDP | 備考 |
|:--|:--|:--|:--|:--|:--|:--|
| Ryzen AI 9 HX 470 | 12C/24T | 5.2 GHz | Radeon 890M (16CU) | 55 | 15–54W | 最上位、Overall 86 TOPS |
| Ryzen AI 7 450 | 8C/16T | 5.1 GHz | Radeon 860M (8CU) | 50 | 15–54W | — |
| Ryzen AI 7 445 | 6C/12T | 4.6 GHz | Radeon 840M (4CU) | 50 | 15–54W | — |
| Ryzen AI 5 435 | 6C/12T | 4.5 GHz | Radeon 840M (4CU) | 50 | 15–54W | — |
| Ryzen AI 5 430 | 4C/8T | 4.5 GHz | Radeon 840M (4CU) | 50 | 15–28W | — |

PRO版: Ryzen AI 9 HX PRO 470、Ryzen AI 7 PRO 450、Ryzen AI 5 PRO 435 など（法人・モバイルワークステーション向け）。

#### XDNA 2 — Ryzen AI 400シリーズ（デスクトップ, 2026年）

対応メモリ: DDR5。プロセスノード: TSMC 4nm。CPU: Zen 5、GPU: RDNA 3.5。ソケット: AM5。コードネーム: Gorgon Point AM5。デスクトップ向けとしては初のXDNA搭載（Copilot+ PC対応）。

| SKU | コア/スレッド | ブースト | iGPU | NPU (TOPS) | TDP | 備考 |
|:--|:--|:--|:--|:--|:--|:--|
| Ryzen AI 7 450G | 8C/16T | 5.1 GHz | Radeon 860M (8CU) | 50 | 65W | デスクトップ初XDNA |
| Ryzen AI 5 440G | 6C/12T | 4.8 GHz | Radeon 840M (4CU) | 50 | 65W | — |
| Ryzen AI 5 435G | 6C/12T | 4.5 GHz | Radeon 840M (4CU) | 50 | 45–65W | — |
| Ryzen AI 7 450GE | 8C/16T | 5.1 GHz | Radeon 860M (8CU) | 50 | 35W | 省電力版 |
| Ryzen AI 5 440GE | 6C/12T | 4.8 GHz | Radeon 840M (4CU) | 50 | 35W | 省電力版 |
| Ryzen AI 5 435GE | 6C/12T | 4.5 GHz | Radeon 840M (4CU) | 50 | 35W | 省電力版 |

PRO版: Ryzen AI 7 PRO 450G / 450GE、Ryzen AI 5 PRO 440G / 440GE、Ryzen AI 5 PRO 435G / 435GE（法人向け）。

ASUS ExpertCenter PN55（ミニPC）などでの採用が確認されています。

## データ型と精度

### 対応データ型

| データ型 | XDNA | XDNA 2 | 用途 |
|:--|:--|:--|:--|
| INT8 | ○ | ○ | 量子化済みCNN/Transformerの高速推論 |
| INT4 | ○ | ○ | 極限量子化LLM推論 |
| BFP16（Block Floating Point 16） | × | ○ | ブロック単位で指数を共有し、INT8並のメモリ効率でFP16に近い精度を実現 |

### BFP16（Block Floating Point 16）の仕組み

XDNA 2で追加されたBFP16は、IEEE 754の通常のFP16（1符号 + 5指数 + 10仮数 = 各要素が独立した指数部を持つ）とは異なるデータ形式です。AMD Quarkの公式ドキュメント（[BFP16 Quantization](https://quark.docs.amd.com/latest/pytorch/tutorial_bfp16.html)）では以下のように定義されています。

**BFP16の構造**:

- **1ブロック = 8要素**
- **共有指数**: 8ビット（ブロック内の最大指数を採用）
- **各要素**: 1ビットの符号 + 7ビットの仮数部（暗黙の1を含む）

```text
通常のFP32（IEEE 754、1要素あたり32ビット）:
  [1符号][8指数][23仮数]  ← 要素ごとに独立した指数部

通常のFP16（IEEE 754、1要素あたり16ビット）:
  [1符号][5指数][10仮数]  ← 要素ごとに独立した指数部

BFP16（ブロック浮動小数点、8要素で共有指数）:
  [8ビット共有指数]                    ← ブロックに1個
  [1符号][7仮数] × 8要素              ← 各要素8ビット = INT8相当
  合計: 8 + (8 × 8) = 72ビット / 8要素 = 9ビット/要素
```

**量子化の手順**（AMD Quark実装に基づく）:

1. **共有指数の決定**: ブロック内8要素の最大指数を共有指数とする
2. **仮数部のシフト**: 各要素の仮数部を、共有指数との差に応じて右シフト（暗黙の1を含む）
3. **丸め処理**: 仮数部の端数ビットを half-to-even 方式で丸めて除去

**BFP16の意義**:

- **INT8並のストレージ効率**: 各要素が8ビット（符号1 + 仮数7）で格納されるため、1要素あたりのメモリ消費はINT8と同等（共有指数のオーバーヘッドはブロック8要素で8ビットのみ）
- **FP16に近い精度**: 仮数部7ビットは通常のFP16の10ビットより少ないが、ブロック内で共有指数を持つため、同一ブロック内の値のスケールが近い場合には精度劣化が小さい
- **量子化はAMD Quarkで実行**: Ryzen AI SoftwareではAMD Quarkツールキットを通じてFP32/FP16モデルをBFP16に変換する。変換は事前キャリブレーションで行い、モデルの再学習は不要

BFP16は「INT8ではダイナミックレンジが足りない（指数部がなく表現範囲が狭い）が、FP16ではメモリ帯域やメモリ容量を圧迫する」というジレンマに対する、ブロック単位で指数を共有することによる妥協策です。共有指数によってブロック内のダイナミックレンジを確保しつつ、各要素は8ビットに収めることでINT8並のメモリ効率を維持します。

### GEMM性能の実測値

AMD公開の論文（arXiv:2512.13282）による、GEMM最適化後のスループット実測値です。

| 世代 | INT8 GEMM | BFP16 GEMM |
|:--|:--|:--|
| XDNA（初代） | 最大 6.76 TOPS | 最大 3.14 TOPS |
| XDNA 2 | 最大 38.05 TOPS | 最大 14.71 TOPS |

XDNA 2はINT8で約5.6倍、BFP16で約4.7倍のスループット向上を達成しています。

## ソフトウェアスタック

### 全体像

```mermaid
graph TD
    subgraph APP["アプリケーション"]
        A1["Copilot+ / LM Studio / 独自アプリ"]
    end
    subgraph FW["フレームワーク層"]
        ONNX["ONNX Runtime<br/>+ Vitis AI EP<br/>（CNN/Transformer）"]
        OGA["OnnxRuntime GenAI<br/>（OGA）<br/>NPU-only / Hybrid"]
        LEM["Lemonade SDK<br/>（マルチベンダーポータビリティ）"]
    end
    subgraph QUANT["量子化ツール"]
        Q1["AMD Quark: FP32/FP16 → INT8/INT4/BFP16"]
    end
    subgraph DRV["ドライバ / ランタイム"]
        W["Windows: AMD NPU Driver"]
        L["Linux: amdxdna.ko + XRT SHIM"]
    end
    subgraph HW["ハードウェア"]
        NPU["AMD XDNA NPU<br/>（AIEタイルアレイ）"]
    end
    APP --> FW
    ONNX --> QUANT
    OGA --> QUANT
    LEM --> ONNX
    LEM --> OGA
    QUANT --> DRV --> HW
```

### ONNX Runtime + Vitis AI Execution Provider

CNNやTransformerモデルのデプロイに使われる主経路です。Vitis AI EP（Execution Provider）が、モデルのどの部分をNPUで実行し、どの部分をiGPUやCPUにフォールバックするかをインテリジェントに判定します。

開発フローは以下のとおりです。

1. 通常どおりモデルを学習（PyTorch / TensorFlow等）
2. ONNXフォーマットにエクスポート
3. AMD Quarkで量子化（INT8/INT4/BFP16）
4. ONNX Runtime + Vitis AI EPで推論実行

### OnnxRuntime GenAI（OGA）による LLM 推論

Ryzen AI Software（1.6以降）は、NPU上のLLM推論に**OnnxRuntime GenAI（OGA）**を使用します。NPUを活用するモードは以下の2つです。

| モード | 計算資源 | 説明 |
|:--|:--|:--|
| **NPU-only** | NPU専用 | NPUの利用率を最大化し、iGPUを他タスクに開放 |
| **Hybrid** | NPU + iGPU動的分担 | prefill/decodeを最適に配分する対話的推論 |

（出典: [Ryzen AI Software 1.6 — LLM Overview](https://ryzenai.docs.amd.com/en/1.6/llm/overview.html)）

NPU-onlyおよびHybridモードはRyzen AI 300シリーズ（Strix Point / Krackan Point）以降でサポートされます。旧世代（Ryzen AI 7000/8000）ではCPU/iGPUのみでの推論となります。

### Lemonade SDK

Lemonade SDKは、OGAを抽象化しマルチベンダーポータビリティを提供する上位SDKです。アプリケーション側はLemonade APIを使い、NPU固有のコードを書く必要がありません。

### Linux ドライバ（amdxdna.ko）

Linux上ではDRM/accelサブシステムのドライバ `amdxdna.ko` がNPUを管理します。

**上流カーネルへの統合経緯**:

| 時期 | 出来事 | 参考 |
|:--|:--|:--|
| 2024年1月 | AMDがamdxdnaドライバをオープンソースとして公開（out-of-tree） | [amd/xdna-driver](https://github.com/amd/xdna-driver) |
| 2024年7月 | 上流カーネルへの正式なパッチ投稿を開始（V1） | [Phoronix: AMD XDNA Ryzen AI Driver Patch](https://www.phoronix.com/news/AMD-XDNA-Ryzen-AI-Driver-Patch) |
| 2024年8月–9月 | V2、V3と11回のレビュー・改訂を経る | [LWN: AMD XDNA driver](https://lwn.net/Articles/990069/) |
| 2024年12月初旬 | `drm-misc-next`ブランチにマージ | [Phoronix: AMDXDNA DRM-Misc-Next](https://www.phoronix.com/news/AMDXDNA-DRM-Misc-Next) |
| 2025年3月24日 | **Linux 6.14 安定版リリース**。`drivers/accel/amdxdna/` として正式にメインラインカーネルに含まれる | [LWN: Linux 6.14](https://lwn.net/Articles/1015309/) |

amdxdnaはオープンソース公開からメインライン統合まで約1年2ヶ月を要しました。Ubuntu 25.04以降、カーネル6.14を含むディストリビューションでは追加インストールなしにNPUを認識します。

**要件**:

- Linux kernel 6.10以上
- `CONFIG_DRM_ACCEL=y`
- `CONFIG_AMD_IOMMU=y`
- XRTベースパッケージ

**主要コンポーネント**:

| コンポーネント | 役割 |
|:--|:--|
| amdxdna.ko | カーネルモジュール。NPUデバイスの管理 |
| XRT SHIM | ユーザースペースランタイム。アプリケーションとドライバの仲介 |
| マイクロコントローラ | NPUファームウェア。コマンド処理、パーティション設定、コンテキスト管理 |
| メールボックス | ドライバ⇔ファームウェア間の通信チャネル |
| PCIeインタフェース | BAR（PSP, SMU, SRAM, Mailbox, Public Register）とMSI-X割り込み |

ファームウェアにはERT（非特権コンテキスト）とMERT（特権コンテキスト）の2種があり、ワークロードの隔離とセキュアな管理が行われます。

## 競合NPUとの比較

### 2026年時点の主要NPU

| 項目 | AMD XDNA 2 | Intel NPU 4 (Lunar Lake) | Qualcomm Hexagon 6th Gen |
|:--|:--|:--|:--|
| ピーク性能 | 55〜60 TOPS | 48 TOPS | 45 TOPS（X Elite）、80〜85 TOPS（X2 Elite） |
| アーキテクチャ | 空間データフロー型（AIEタイル配列） | MAC Array + DMA | DSP型 |
| 主な精度 | INT8, INT4, BFP16 | INT8, INT4, **FP16** | INT8, INT4 |
| FP16対応 | BFP16（ブロック単位共有指数。IEEE 754 FP16とは異なる） | ネイティブFP16（IEEE 754） | × |
| CPU統合 | Zen 5 | P/E Core + Xe2 GPU | Oryon（Arm） |
| ISA | x86-64 | x86-64 | Arm |
| プロセスノード | TSMC 4nm | Intel 18A / Intel 4 | TSMC 3nm |
| メモリ | DDR5 / LPDDR5X（外付け） | LPDDR5X（オンパッケージ、最大32GB） | LPDDR5X（オンパッケージ、最大48GB） |
| ドライバ状況 | Windows / Linux（カーネル統合済み） | Windows / Linux（OpenVINO） | Windows / Android |
| 主な開発フレームワーク | ONNX Runtime + Vitis AI EP, OGA | OpenVINO, ONNX Runtime | AI Engine Direct SDK |

### 比較のポイント

**x86互換性**: AMD XDNA 2とIntel NPU 4はx86-64プラットフォームに統合されているため、既存のx86アプリケーション資産をそのまま使えます。QualcommはArm ISAのため、x86エミュレーション（Windows on Arm）が必要な場面があります。

**FP16精度**: Intel Lunar LakeはIEEE 754ネイティブFP16をサポートしており、量子化なしで高精度推論が可能です。AMD XDNA 2のBFP16はブロック単位で指数を共有する形式であり、IEEE 754 FP16とは異なります。各要素の仮数部は7ビット（FP16の10ビットより短い）のため、ブロック内の値のスケールが大きく異なる場合には精度が低下する可能性があります。一方、ストレージ効率ではINT8並を実現します。Qualcomm HexagonはINT8/INT4が中心で、FP16サポートはCPU/GPU側に依存します。

**総合性能 vs NPU単体性能**: NPUのTOPS値だけでなく、CPU + GPU + NPUの合計システムTOPSや、実際のモデルでのtokens/s、TTFTで比較することが重要です。

## 実際の利用シーン

### Copilot+ PC

MicrosoftのCopilot+ PC認定には**40 TOPS以上のNPU性能**が要件とされています。XDNA 2は55〜60 TOPSでこの要件を満たし、以下のようなAI機能をローカルで実行できます。

- **Windows Recall**: 画面上のコンテンツをAIで索引化
- **Cocreator**: ペイントでのAI画像生成アシスト
- **Live Captions with Translation**: リアルタイム字幕翻訳
- **Windows Studio Effects**: AIカメラエフェクト

### ローカルLLM推論

XDNA 2のNPUを活用して、クラウドに接続せずにLLMをローカル実行できます。OnnxRuntime GenAI（OGA）経由でNPU-onlyモードまたはHybridモード（NPU + iGPU）を選択し、省電力で推論を行います。LM Studioなどのデスクトップアプリからも、Ryzen AI搭載PCであればNPUを活用できるケースがあります。

### エッジAI / 組み込み

AMD Ryzen AI Embedded P100/X100シリーズは、XDNA 2 NPU（最大50 TOPS）をエッジAI向けに提供しています。

- 産業用画像検査
- ロボットのリアルタイム推論
- 医療画像の前処理
- 小売業の在庫認識

TDPは15〜54W（典型28W）で、ファンレス〜小型筐体で運用可能です。

## XDNAの設計思想まとめ

XDNAが他のアクセラレータと異なる設計上のポイントを整理します。

### 1. 決定論的な実行

データの移動はDMAエンジンが事前にスケジュール済みであり、実行時の「待ち」が発生しにくい設計です。これにより、レイテンシの予測可能性（determinism）が高く、リアルタイム性が求められるエッジ用途にも適しています。

### 2. スケーラビリティ

タイルアレイはモジュラー構造で、タイル数を変えるだけで異なる性能・消費電力・面積のNPUを構成できます。実際に、Phoenix（4×5 = 20タイル）からStrix Point（4×8 = 32タイル）への拡張は、アーキテクチャの設計変更なしにタイル数を増やすことで実現されています。

### 3. プログラマビリティ

XDNAは固定機能ハードウェアではなく、各タイルがプログラム可能なプロセッサです。新しいAIオペレータや演算パターンが登場しても、ファームウェアやコンパイラの更新で対応できます。AMDは「ソフトウェアプログラマビリティにより数分でコンパイル可能」と述べています。

### 4. 電力効率

キャッシュからの繰り返しフェッチを避け、データをオンチップメモリに局所化する設計は、同じ演算量に対してCPU比で10〜40倍の電力効率を実現します。バッテリー駆動のノートPCでAI推論を「常時ON」にするためには、この電力効率が不可欠です。

## まとめ

AMD XDNAは、Xilinx AI Engineの空間データフロー技術をクライアントAPU向けに最適化したNPUアーキテクチャです。2Dタイルアレイ上の計算タイルがDMAベースの決定論的データ移動で協調し、低消費電力で高スループットなAI推論を実現します。

XDNA（10 TOPS）→ XDNA 2（55 TOPS）→ 第3世代（10倍超予告）と急速に進化しており、ソフトウェアスタック（ONNX Runtime + Vitis AI EP、OnnxRuntime GenAI、Lemonade SDK）も整備が進んでいます。Copilot+ PC要件を満たすAI PCの中核技術として、ローカルLLM推論やエッジAIの普及を支える存在になりつつあります。

## 参考資料

- [AMD XDNA Architecture（公式）](https://www.amd.com/en/technologies/xdna.html)
- [AMD XDNA（Wikipedia）](https://en.wikipedia.org/wiki/AMD_XDNA)
- [WP506: Xilinx AI Engines and Their Applications（AIEアーキテクチャホワイトペーパー）](https://spiritelectronics.com/pdf/wp506-ai-engine.pdf)
- [AM009: Versal AI Engine Architecture Manual](https://docs.amd.com/r/en-US/am009-versal-ai-engine/AI-Engine-Array-Overview)
- [AMD XDNA NPU in Ryzen AI Processors（IEEE Xplore）](https://ieeexplore.ieee.org/document/10592049/)
- [Striking the Balance: GEMM Performance Optimization Across Generations of Ryzen AI NPUs（arXiv:2512.13282）](https://arxiv.org/abs/2512.13282)
- [Ryzen AI Software Documentation](https://ryzenai.docs.amd.com/)
- [Ryzen AI Software 1.6 — LLM Overview（実行モード比較表の出典）](https://ryzenai.docs.amd.com/en/1.6/llm/overview.html)
- [OGA NPU Execution Mode — Ryzen AI Software](https://ryzenai.docs.amd.com/en/latest/npu_oga.html)
- [AMD Quark — BFP16 (Block Floating Point) Quantization Tutorial](https://quark.docs.amd.com/latest/pytorch/tutorial_bfp16.html)
- [amd/RyzenAI-SW（GitHub — AMD公式のRyzen AIソフトウェアリポジトリ）](https://github.com/amd/RyzenAI-SW)
- [amd/xdna-driver（GitHub）](https://github.com/amd/xdna-driver)
- [accel/amdxdna NPU driver — Linux Kernel Documentation](https://www.kernel.org/doc/html/next/accel/amdxdna/index.html)
- [AMD NPU Hardware Documentation（Linux Kernel）](https://docs.kernel.org/accel/amdxdna/amdnpu.html)
- [AMDXDNA Driver For Ryzen AI Now Ready To Appear In The Linux Kernel（Phoronix, 2024年12月）](https://www.phoronix.com/news/AMDXDNA-DRM-Misc-Next)
- [AMDXDNA Submitted For Linux 6.14（Phoronix）](https://www.phoronix.com/news/Linux-6.14-DRM-Feature-Pull)
- [Linux 6.14（LWN.net, 2025年3月24日リリース）](https://lwn.net/Articles/1015309/)
- [AMD XDNA driver パッチレビュー（LWN.net）](https://lwn.net/Articles/990069/)
- [AMD Ryzen AI Max+ — Run up to 128B LLMs on Windows with LM Studio（AMD Blog）](https://www.amd.com/en/blogs/2025/amd-ryzen-ai-max-upgraded-run-up-to-128-billion-parameter-llms-lm-studio.html)
- [AMD Confirms Next-Gen CPU and GPU Roadmaps](https://www.kad8.com/hardware/amd-confirms-next-gen-cpu-and-gpu-roadmaps/)
- [NPU Comparison 2026: Intel vs Qualcomm vs AMD vs Apple](https://localaimaster.com/blog/npu-comparison-2026)
- [AMD Acquires Xilinx](https://www.amd.com/en/corporate/xilinx-acquisition.html)