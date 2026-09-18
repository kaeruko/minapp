import 'api.dart';

String girlsMessageFor(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'invalid_credentials':
        return 'IDかパスワードが違うみたい。もう一度確認してね。';
      case 'login_id_conflict':
        return 'そのIDはもう使われています。別のIDにしてね。';
      case 'invalid_invite_code':
      case 'invite_not_found':
        return 'グループIDが見つからないみたい。文字を確認してね。';
      case 'invite_expired':
        return 'このグループIDは期限切れです。オーナーに新しいIDを発行してもらってね。';
      case 'already_member':
        return 'もうこのグループに参加しているよ。';
      case 'group_full':
        return 'このグループは参加人数の上限に達しています。';
      case 'group_limit_reached':
        return '参加できるグループ数の上限に達しています。';
      case 'rate_limited':
        return '操作が続きすぎたみたい。少し待ってからもう一度試してね。';
      default:
        return error.message;
    }
  }
  if (error is ArgumentError || error is FormatException) {
    return '入力またはサーバーから届いたデータの形式を確認できませんでした。';
  }
  return '処理に失敗しました: $error';
}
