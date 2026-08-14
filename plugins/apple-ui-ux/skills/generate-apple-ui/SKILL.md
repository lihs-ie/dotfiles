---
name: generate-apple-ui
description: 仕様からiOS・iPadOSのUI/UX設計を生成し、Claude DesignまたはOpen Designで3方向を比較し、重要状態を展開して、ハッシュ付き人間承認まで進める。Use when the user asks to design or generate a new native iOS/iPadOS screen or flow from requirements for SwiftUI, UIKit, or a mixed app. Do not use for adapting an existing interface; use conform-apple-ui instead.
---

# Apple公開UI/UXプロファイルから生成する

仕様をsemantic UI intentへ変換し、Apple公開資料に基づくprofileを適用する。見た目の類似だけで適合を主張しない。

## 必ず先に読む

- `../../references/workflow-contract.md`
- `../../schemas/apple-ui-ux-spec.schema.json`
- 対象となる`../../profiles/*.yaml`
- 適用ruleを探すときだけ`../../rules/rules.yaml`
- 根拠確認が必要なruleについてだけ`../../evidence/registry.yaml`

## ワークフロー

1. 対象repo、仕様、既存design system、deployment target、framework構成を調べる。事実をユーザーへ質問しない。
2. 画面目的、主要task、情報、状態、device、profile、brand制約のうち未決定の判断だけを一問ずつ聞く。毎回推奨回答を示す。
3. `workflow: generate`の`design/apple-ui-ux/apple-ui-ux-spec.yaml`を作り、schemaで検証する。SwiftUI、UIKit、mixedを同格に扱う。
4. Claude DesignまたはOpen Designの一方をbackendとして選ぶ。利用不能なら停止し、通常チャット生成へfallbackしない。
5. system-standard、brand-emphasis、alternative-architectureの重複しない3方向を作る。すべてL1/L2違反のない候補にする。
6. ユーザーが選んだ1方向だけをpopulated、empty、loading、error、該当するpermission/destructive、iPhone、iPad、Light、Dark、標準Dynamic Type、accessibility最大へ展開する。
7. design成果物をspecの`artifacts`へ登録し、`../../scripts/approval_gate.py validate-spec`を実行する。
8. 成果物と適用rule、L3/L4助言、未検証項目を提示する。ユーザーが明示承認するまで実装へ進まない。
9. 承認された場合だけ`approval_gate.py approve --confirm APPROVE`を実行する。承認後にdigestが変われば実装を停止する。

## Foundation 0.1の境界

この版は承認済みdesign handoffまでを保証する。native実装adapterと全verifierは後続phaseであり、実行していない検査を`pass`と報告しない。

## 禁止

- `Apple certified`、`Apple公式UI再現`、画像が似ていることによる適合宣言
- 公開根拠のない固定spacing、radius、font size、RGBを普遍ruleにすること
- Claude Design/Open Designを通さない代替design生成
- 承認記録の自動生成、承認後designの無断変更
- SwiftUIとUIKitの一方へ理由なく全面移行すること
