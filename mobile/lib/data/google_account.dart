import 'package:google_sign_in/google_sign_in.dart';

/// Scopes are requested separately from sign-in in google_sign_in 7.x, so the
/// app only asks for library access when you actually import something.
const youtubeReadonlyScope =
    'https://www.googleapis.com/auth/youtube.readonly';

/// Supplied at build time:
///   flutter build apk --dart-define=GOOGLE_CLIENT_ID=xxxx.apps.googleusercontent.com
///
/// Kept out of source on purpose: it identifies the app, it is not a secret,
/// but hardcoding it would tie the repository to one developer account.
const googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');

class GoogleUser {
  const GoogleUser({this.email, this.displayName, this.photoUrl});

  final String? email;
  final String? displayName;
  final String? photoUrl;
}

class GoogleAccountException implements Exception {
  const GoogleAccountException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thin wrapper over google_sign_in with readable failures.
class GoogleAccount {
  bool _initialized = false;

  bool get isConfigured => googleClientId.isNotEmpty;

  GoogleSignInAccount? _account;

  GoogleUser? get user => _account == null
      ? null
      : GoogleUser(
          email: _account!.email,
          displayName: _account!.displayName,
          photoUrl: _account!.photoUrl,
        );

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    if (!isConfigured) {
      throw const GoogleAccountException(
        'Google sign-in is not configured in this build. Rebuild with '
        '--dart-define=GOOGLE_CLIENT_ID=<your OAuth client id>.',
      );
    }
    await GoogleSignIn.instance.initialize(clientId: googleClientId);
    _initialized = true;
  }

  /// Silent when possible, interactive otherwise.
  Future<GoogleUser?> signIn() async {
    await _ensureInitialized();
    try {
      _account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      throw GoogleAccountException(error.description ?? error.code.name);
    }
    return user;
  }

  Future<void> signOut() async {
    if (!_initialized) return;
    await GoogleSignIn.instance.signOut();
    _account = null;
  }

  /// Headers for a REST call, prompting for the YouTube scope the first time.
  Future<Map<String, String>> libraryHeaders() async {
    await _ensureInitialized();
    final account = _account;
    if (account == null) {
      throw const GoogleAccountException('Sign in first');
    }

    final headers = await account.authorizationClient.authorizationHeaders(
      [youtubeReadonlyScope],
      promptIfNecessary: true,
    );
    if (headers == null) {
      throw const GoogleAccountException(
        'Access to your YouTube library was not granted',
      );
    }
    return headers;
  }
}
