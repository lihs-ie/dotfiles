# haskell_completion_doctor.nvim

Haskell の補完が止まった時に、原因と解決方法を floating panel に表示する小さな Neovim プラグイン。

表示内容:

- HLS 接続状態
- 現在の diagnostics
- `:messages` から抽出した HLS / Cabal / cradle 関連ログ
- Cabal / cradle 系の典型原因
- not-in-scope など型チェック失敗時の解決方法

## Usage

```vim
:HCDoc
```

またはキーマップで開く。

```vim
<leader>hd
```

閉じる。

```vim
:HCDocClose
<leader>hD
```

長いコマンド名も使える。

```vim
:HaskellCompletionDoctor
```

自動表示はしない。明示的に `:HCDoc` を呼んだ時だけ floating panel を開く。

## Test

```bash
nvim --headless -u NONE -c 'luafile tests/haskell_completion_doctor_spec.lua'
```
