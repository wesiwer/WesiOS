import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/connectors/wesi_connector_api.dart';

void main() {
  test('connector credential parser exposes metadata only', () {
    final c = WesiConnectorCredential.fromJson(<String, dynamic>{
      'credentialId': 'wai_conn_github_abcdefghijklmnopqrstuvwxyz',
      'provider': 'github',
      'accountLogin': 'wesi',
      'accountId': '42',
      'scopes': ['repo', 'workflow'],
      'status': 'active',
      'accessToken': 'must-not-be-modeled'
    });
    expect(c.accountLogin, 'wesi');
    expect(c.scopes, ['repo', 'workflow']);
    expect(c.toString(), isNot(contains('must-not-be-modeled')));
  });
  test('GitHub device flow accepts only expected https github verification URI',
      () {
    final ok = WesiGithubDeviceFlow.fromJson(<String, dynamic>{
      'flowId': 'wai_conn_flow_abcdefghijklmnopqrstuvwxyz',
      'userCode': 'ABCD-EFGH',
      'verificationUri': 'https://github.com/login/device',
      'expiresAt': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 10))
          .toIso8601String(),
      'interval': 5
    });
    expect(ok.verificationUri.host, 'github.com');
    expect(
        () => WesiGithubDeviceFlow.fromJson(<String, dynamic>{
              'flowId': 'wai_conn_flow_abcdefghijklmnopqrstuvwxyz',
              'userCode': 'ABCD-EFGH',
              'verificationUri': 'https://evil.test/device',
              'expiresAt': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 10))
                  .toIso8601String(),
              'interval': 5
            }),
        throwsFormatException);
  });
}
