# 共通ワークフロー契約

## 目的

このプラグインはAppleの認定を主張しない。特定versionの公開資料から固定した`Apple Public UI/UX Evidence Profile`への適合を、再現可能な成果物で示す。

## 公開入口

- `generate-apple-ui`: 仕様から新しいUI/UX designを作る。
- `conform-apple-ui`: 既存UI/UXを監査し、適合変更後のdesignを作る。audit-onlyでは変更しない。

Rule、Evidence、Profile、Schema、approval gateは両入口で共有する。

## 必須ライフサイクル

1. repoから分かる事実を観測する。
2. 未決定のproduct判断を依存順に一問ずつ解決する。各質問に推奨回答を添える。
3. `apple-ui-ux-spec.yaml`を作り、適用profileとruleを固定する。
4. Claude DesignまたはOpen Designの一方で重複しない3方向を生成する。
5. ユーザーが1方向を選ぶ。
6. 選択案を重要状態、iPhone/iPad、Light/Dark、標準/最大Dynamic Typeへ展開する。
7. L1/L2監査とschema検証を行う。
8. ユーザーへ成果物と未検証項目を提示する。
9. 明示的な`APPROVE`相当の意思表示を受けた場合だけapproval recordを生成する。
10. 実装開始前と完了時にapproval digestを再検証する。

Design backendを利用できない場合は停止する。通常チャット、画像生成、別のHTML生成へ暗黙fallbackしない。

## 段階別の最小終了レシピ

### Design backendを利用できない

既知のproduct判断を失わないため、`design_status: draft`のspecを残す。schemaの`artifacts`には`design/apple-ui-ux/artifacts/backend-unavailable.yaml`を`kind: audit-report`として1件登録する。このartifactへbackendごとの確認結果、停止理由、`fallback_used: false`、再開条件、未実行検査の`not_verified`を記録する。approvalとnative実装は作らない。

### Audit-only

file作成を明示されていなければ応答内で監査レポートを返し、repoを変更しない。レポートは`Scope`、`Framework boundary`、`L1/L2 failures`、`L3 deviations`、`L4 advice`、`not_verified`、`Preserved behavior/data meaning`、`Next gate`をこの順で含める。根拠不足は推測せず`not_verified`へ送る。

### Review-readyまたは承認要求

先に次を実行する。`<plugin-root>`はこのSkillを含むplugin root、`<project-root>`は対象repoの絶対pathへ置換する。

```bash
python3 <plugin-root>/scripts/approval_gate.py validate-spec --project-root <project-root>
```

`behavior_changes`に`pending`が1件でもあれば、視覚承認と分離して必要な判断を一問だけ提示し、approvalを作らず停止する。すべて解決し、成果物レビュー後の明示承認を得た場合だけ次を実行する。

```bash
python3 <plugin-root>/scripts/approval_gate.py approve --project-root <project-root> --approved-by <reviewer> --confirm APPROVE
```

## 成果物

対象repoの`design/apple-ui-ux/`へ次を置く。

```text
design/apple-ui-ux/
├── apple-ui-ux-spec.yaml
├── approval.yaml
└── artifacts/
```

`apple-ui-ux-spec.yaml`を正本とし、Open Design用`DESIGN.md`は生成ビューとする。approvalはspecと全design artifactのSHA-256を固定する。承認後に1 byteでも変われば未承認へ戻す。

## 証拠と判定

優先順位は`L1 > L2 > L3 > L4`とする。

| Level | 意味 | 判定 |
|---|---|---|
| L1 | Apple公開規範 | mandatory ruleはHard Gate |
| L2 | documented platform contract | Hard Gate |
| L3 | Apple公式アプリの反復観測 | warningまたはconditional pass |
| L4 | AI Vision・専門家heuristic | advisoryのみ |

結果は`pass`、`conditional_pass`、`fail`、`not_verified`を使う。検査未実行を`pass`にしない。

### 証拠充足による結果昇格

各ruleを必ず次の順序で1回だけ判定する。

| 順序 | 条件 | 最終結果 |
|---|---|---|
| 1 | predicate評価に必要な入力の1つ以上がscope外・runtime未取得・下流未追跡 | `not_verified` |
| 2 | 必要入力をすべて観測し、predicateが偽。repo内に承認済み例外なし | `fail` |
| 3 | predicateは真だが、`measurement.kind`の検査が未完了 | `not_verified` |
| 4 | 必要measurementを完了し、predicateが真 | `pass`またはL3/L4に応じた`conditional_pass` |

`static_candidate`は説明用labelであり最終結果ではない。同じruleを同一scopeで複数の最終結果へ載せない。部分sourceに経路が見えないことを、app全体に経路が存在しない証拠として扱わない。

sourceだけで必要入力をすべて観測できるruleは、runtimeを含む`measurement.kind`でも手順2へ進める。固定point sizeと例外不在をrepo内で確認した場合は`TYP-001: fail`にできる一方、clippingを実測していない`TYP-002`は手順1の`not_verified`とする。`BRG-001`ではrepresentableの全更新経路をscope内で確認し、sourceから渡るmutable入力の一部が更新不能または更新処理から欠落していると確定できれば`fail`、更新副作用や別extensionがscope外なら`not_verified`とする。

- UI actionからcallbackが呼ばれるだけでは`destructive_commit`とみなさない。永続変更点、確認取得点、取消経路を追跡できない場合は`DST-001: not_verified`とする。
- ruleに書かれていない追加リスクは、そのruleのfailure理由へ混ぜない。たとえば`BRG-001`はsource stateとdestination configurationの同期を判定し、domain identifierの意味保存は別の業務不変条件として報告する。

## Framework境界

SwiftUI、UIKit、mixedを同格に扱う。標準componentを優先するが、適合を理由にframeworkを全面移行しない。bridge境界は独立した検査対象とする。

## 例外

例外はrule、owner、reason、expiry、profile、design digest、accessibility evidenceを必須とする。期限切れ、証拠不足、未承認の例外はHard Failとする。

## 表現制約

使用可能:

> Apple公開UI/UX根拠プロファイル `<profile>@<snapshot>` 適合

禁止:

- Apple certified
- Apple公式アプリを再現
- Appleが認定したUI
- L3/L4所見をAppleの要求として表現すること
