# rubric pack: OIDC / OAuth

「つながっているように見えて security property が満たされていない」典型領域。
「ログインできた」だけでなく **PKCE・state/redirect・token exchange・session persistence** を
end-to-end で検証する。

## 追加判定項目
- Authorization Code flow で **PKCE** が使われている (RFC 7636)。
- callback 後に server-side session / token store が **更新** される (callback 成功だけでは不十分)。
- 保護 API / page が **新 session で通る** (read-back)。
- logout / token refresh の read-back が検証されている。

## 推奨証拠
- contract test で IdP metadata / expected token response shape を固定。
- E2E で「login 開始→IdP→callback→session 作成→保護画面 read-back」。
- mock IdP だけに頼らず、staging 実 IdP か protocol-level fixture を 1 本持つ。
