from pathlib import Path

path = Path('apps/mobile/lib/girls_app.dart')
text = path.read_text(encoding='utf-8')

class_marker = 'class _GirlsAuthPageState extends State<GirlsAuthPage> {'
class_start = text.find(class_marker)
if class_start < 0:
    raise RuntimeError('Girls auth state class not found')

next_class_marker = '\nclass GirlsGroupsPage extends StatefulWidget {'
class_end = text.find(next_class_marker, class_start)
if class_end < 0:
    raise RuntimeError('GirlsGroupsPage marker not found after auth state')

auth_block = text[class_start:class_end]
start_marker = "                    const SizedBox(height: 16),\n                    const Text(\n                      'かわいいアプリを、友達といっしょに。',"
start = auth_block.find(start_marker)
if start < 0:
    raise RuntimeError('Existing Girls auth form start marker not found')

end_marker = "\n                  ],\n                ),\n              ),\n            ),\n          ),\n        ),\n      ),\n    );\n  }\n}"
end = auth_block.find(end_marker, start)
if end < 0:
    raise RuntimeError('Existing Girls auth form end marker not found')

replacement = '''                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (_creating) ...<Widget>[
                            const Text(
                              '新規登録',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _lavenderDark,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'メールアドレスや電話番号はいらないよ。',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF8C7893),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],
                          TextField(
                            key: const Key('girls-login-id'),
                            controller: _loginId,
                            enabled: !_busy,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: InputDecoration(
                              labelText: 'Login ID / ユーザー名',
                              floatingLabelBehavior: FloatingLabelBehavior.always,
                              prefixIcon: const Icon(
                                Icons.key_rounded,
                                color: _lavender,
                              ),
                              filled: true,
                              fillColor: const Color(0xFFFFFEFC),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 16,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(28),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD7C7E8),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(28),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD7C7E8),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(28),
                                borderSide: const BorderSide(
                                  color: _lavender,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            key: const Key('girls-password'),
                            controller: _password,
                            enabled: !_busy,
                            obscureText: true,
                            decoration: InputDecoration(
                              labelText: 'Password / パスワード',
                              floatingLabelBehavior: FloatingLabelBehavior.always,
                              prefixIcon: const Icon(
                                Icons.favorite_border_rounded,
                                color: Color(0xFFD59AB6),
                              ),
                              filled: true,
                              fillColor: const Color(0xFFFFFEFC),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 16,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(28),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD7C7E8),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(28),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD7C7E8),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(28),
                                borderSide: const BorderSide(
                                  color: _lavender,
                                  width: 1.5,
                                ),
                              ),
                            ),
                            onSubmitted: (_) {
                              if (!_creating && !_busy) _login();
                            },
                          ),
                          if (_creating) ...<Widget>[
                            const SizedBox(height: 14),
                            TextField(
                              key: const Key('girls-password-confirm'),
                              controller: _passwordConfirm,
                              enabled: !_busy,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: 'Password again / もう一度',
                                floatingLabelBehavior: FloatingLabelBehavior.always,
                                prefixIcon: const Icon(
                                  Icons.favorite_rounded,
                                  color: Color(0xFFD59AB6),
                                ),
                                filled: true,
                                fillColor: const Color(0xFFFFFEFC),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 16,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(28),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFD7C7E8),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(28),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFD7C7E8),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(28),
                                  borderSide: const BorderSide(
                                    color: _lavender,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_legalError != null)
                              Row(
                                children: <Widget>[
                                  const Expanded(
                                    child: Text('利用規約を読み込めませんでした。'),
                                  ),
                                  TextButton(
                                    onPressed: _loadLegal,
                                    child: const Text('再読み込み'),
                                  ),
                                ],
                              )
                            else if (legal == null)
                              const Center(child: CircularProgressIndicator())
                            else ...<Widget>[
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _accepted,
                                onChanged: _busy
                                    ? null
                                    : (bool? value) {
                                        setState(
                                          () => _accepted = value ?? false,
                                        );
                                      },
                                title: const Text(
                                  '利用規約とプライバシーポリシーに同意します',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                controlAffinity: ListTileControlAffinity.leading,
                              ),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                children: <Widget>[
                                  TextButton(
                                    onPressed: () => _showLegal(legal.terms),
                                    child: const Text('利用規約を読む'),
                                  ),
                                  TextButton(
                                    onPressed: () => _showLegal(legal.privacy),
                                    child: const Text('プライバシーを読む'),
                                  ),
                                ],
                              ),
                            ],
                          ] else ...<Widget>[
                            const SizedBox(height: 8),
                            const Text(
                              'パスワードを忘れた場合は、登録時に保存した復旧コードを使います。',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFFAA91A4),
                                fontSize: 11,
                              ),
                            ),
                          ],
                          if (_error != null) ...<Widget>[
                            const SizedBox(height: 12),
                            _GirlsError(message: _error!),
                          ],
                          const SizedBox(height: 16),
                          Container(
                            height: 54,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: _creating
                                    ? const <Color>[
                                        Color(0xFF9ADFC8),
                                        Color(0xFF62C9AD),
                                      ]
                                    : const <Color>[
                                        Color(0xFFD7C2F1),
                                        Color(0xFFA77BD5),
                                      ],
                              ),
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: const <BoxShadow>[
                                BoxShadow(
                                  color: Color(0x33745B9E),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: FilledButton.icon(
                              key: const Key('girls-auth-submit'),
                              onPressed: _busy
                                  ? null
                                  : (_creating ? _register : _login),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                disabledBackgroundColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                              ),
                              icon: _busy
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Icon(
                                      _creating
                                          ? Icons.favorite_rounded
                                          : Icons.login_rounded,
                                    ),
                              label: Text(
                                _busy
                                    ? '確認しています…'
                                    : _creating
                                        ? '新規登録する'
                                        : 'ログイン',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: <Widget>[
                              const Expanded(
                                child: Divider(color: Color(0xFFE0CFD7)),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(
                                  _creating ? 'すでに登録済み？' : 'はじめての方',
                                  style: const TextStyle(
                                    color: Color(0xFF9A8793),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const Expanded(
                                child: Divider(color: Color(0xFFE0CFD7)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 50,
                            child: OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () {
                                      setState(() {
                                        _creating = !_creating;
                                        _error = null;
                                      });
                                    },
                              style: OutlinedButton.styleFrom(
                                backgroundColor: _creating
                                    ? Colors.white.withValues(alpha: .72)
                                    : const Color(0xFFA7E2CE),
                                foregroundColor: _creating
                                    ? _lavenderDark
                                    : const Color(0xFF356F61),
                                side: BorderSide(
                                  color: _creating
                                      ? const Color(0xFFD7C7E8)
                                      : const Color(0xFF70C8AD),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(26),
                                ),
                              ),
                              icon: Icon(
                                _creating
                                    ? Icons.arrow_back_rounded
                                    : Icons.favorite_rounded,
                              ),
                              label: Text(
                                _creating ? 'ログインに戻る' : '新規登録はこちら',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),'''

new_auth_block = auth_block[:start] + replacement + auth_block[end:]
if new_auth_block == auth_block:
    raise RuntimeError('Girls auth form patch produced no change')

new_text = text[:class_start] + new_auth_block + text[class_end:]
path.write_text(new_text, encoding='utf-8', newline='\n')
