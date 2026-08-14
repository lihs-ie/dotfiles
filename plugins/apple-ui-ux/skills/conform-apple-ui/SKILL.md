---
name: conform-apple-ui
description: 既存のiOS・iPadOS UI/UXを監査し、Apple公開根拠profileとの差分から変換後designを作り、Claude DesignまたはOpen Designでの人間承認まで進める。Use when the user asks to review, audit, redesign, modernize, or adapt an existing SwiftUI, UIKit, or mixed native interface. Supports audit-only mode and must not modify code in that mode.
---

# 既存UIをApple公開UI/UXプロファイルへ適合させる

既存の業務挙動とデータ意味を保存しながら、公開根拠で説明できる差分だけを設計変更へ送る。

## 必ず先に読む

- `../../references/workflow-contract.md`
- `../../schemas/apple-ui-ux-spec.schema.json`
- 対象となる`../../profiles/*.yaml`
- 適用ruleを探すときだけ`../../rules/rules.yaml`
- 根拠確認が必要なruleについてだけ`../../evidence/registry.yaml`

## ワークフロー

1. 対象repo、実装、navigation entrypoint、既存test、screenshot、framework境界を調べる。
2. 適用profileとscreen scopeを確定し、L1/L2 failure、L3 deviation、L4 advice、`not_verified`を分離した監査結果を作る。
3. audit-only指定ならレポートを応答内に出して終了する。ユーザーがfile出力を明示しない限り、監査対象repoへreport fileを含む新規fileを作らず、既存fileも変更しない。design生成、approval生成、コード変更を行わない。
4. 変更する場合は`workflow: conform`の`design/apple-ui-ux/apple-ui-ux-spec.yaml`へ現状、保存すべき挙動、提案変更、挙動変更候補を記録する。
5. Claude DesignまたはOpen Designの一方で、監査差分を反映した3方向を作る。backend利用不能なら停止する。
6. ユーザーが選択した1方向だけを重要状態・device・appearance・Dynamic Typeへ展開する。
7. 業務logicまたは永続dataの意味を変える提案はdesign変更と分離し、追加承認がない限りspecの`behavior_changes`を未承認のままにする。
8. `../../scripts/approval_gate.py validate-spec`を実行し、成果物、差分、適用rule、例外、未検証項目を提示する。
9. 明示承認された場合だけdigest付きapprovalを作る。digest不一致なら実装を停止する。

## 変更境界

UI、navigation、accessibility、interactionは変更候補にできる。削除確認、permission timing、selection保持などUX安全性に必要な挙動変更は別承認とする。Apple適合を理由にdomain logicを書き換えない。

## Foundation 0.1の境界

この版は承認済みdesign handoffまでを保証する。native code修正と全verifierは後続phaseであり、実行していない検査は`not_verified`とする。

## 禁止

- Apple純正アプリのpixel copyや非公開componentの推定
- L3/L4をApple要求として扱うこと
- audit-onlyでのfile変更
- backendなしのdesign生成fallback
- 未承認designまたはdigest不一致designの実装
- framework全面移行を適合要件として強制すること
