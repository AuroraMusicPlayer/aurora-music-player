import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Scopes are requested separately from sign-in in google_sign_in 7.x, so the
/// app only asks for library access when you actually import something.
/// Read/write on the account's YouTube data. Needed for two-way sync: likes
/// and playlists are written back, not just read.
const youtubeWriteScope = 'https://www.googleapis.com/auth/youtube';

/// Supplied at build time:
///   flutter build apk --dart-define=GOOGLE_CLIENT_ID=xxxx.apps.googleusercontent.com
///
/// Kept out of source on purpose: it identifies the app, it is not a secret,
/// but hardcoding it would tie the repository to one developer account.
const googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');

/// The *Web* client id. Android's Credential Manager presents this as the
/// server client during token exchange; without it, sign-in fails with
/// ApiException 10 (DEVELOPER_ERROR).
const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

/// Android matches its OAuth client by package name + SHA-1, so this id is not
/// sent anywhere — but recording it makes the build configuration complete and
/// self-documenting.
const googleAndroidClientId =
    String.fromEnvironment('GOOGLE_ANDROID_CLIENT_ID');

/// Raised when Google rejects the stored token. Apps in Testing mode get a new
/// consent every seven days, so this is routine rather than exceptional.
class GoogleAuthExpired implements Exception {
  const GoogleAuthExpired();

  @override
  String toString() =>
      'Your Google session expired. Reconnect to keep syncing — Testing-mode '
      'apps need re-authorisation every seven days.';
}

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

  /// iOS needs its own client id compiled in (plus the reversed URL scheme);
  /// Android only needs the OAuth client to exist in the project, matched by
  /// package + SHA-1. Reporting "configured" on the wrong platform would show
  /// a button that cannot work.
  bool get isConfigured {
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return googleClientId.isNotEmpty;
    }
    return googleAndroidClientId.isNotEmpty || googleServerClientId.isNotEmpty;
  }

  GoogleSignInAccount? _account;

  GoogleUser? get user => _account == null
      ? null
      : GoogleUser(
          email: _account!.email,
          displayName: _account!.displayName,
          photoUrl: _account!.photoUrl,
        );

  /// Explains what a given build is missing, so the app never just says
  /// "not configured".
  String get missingConfigHint {
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return 'This iOS build has no GOOGLE_CLIENT_ID compiled in. Rebuild with '
          '--dart-define-from-file=google.json containing your iOS client id.';
    }
    return 'This Android build has no GOOGLE_ANDROID_CLIENT_ID or '
        'GOOGLE_SERVER_CLIENT_ID compiled in. Rebuild with '
        '--dart-define-from-file=google.json.';
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    if (!isConfigured) {
      throw const GoogleAccountException(
        'Google sign-in is not configured in this build. Rebuild with '
        '--dart-define=GOOGLE_CLIENT_ID=<your OAuth client id>.',
      );
    }
    await GoogleSignIn.instance.initialize(
      // iOS uses the iOS client id directly; Android matches its package +
      // SHA-1 through the Android client and needs the web client as server.
      clientId: googleClientId.isEmpty ? null : googleClientId,
      serverClientId:
          googleServerClientId.isEmpty ? null : googleServerClientId,
    );
    _initialized = true;
  }

  /// Silent when possible, interactive otherwise.
  Future<GoogleUser?> signIn() async {
    await _ensureInitialized();
    try {
      _account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      final description = (error.description ?? '').toLowerCase();

      // Android refuses to sign in without a server client; the engine error
      // says so in its own words, which is unhelpful in a settings screen.
      if (description.contains('server client') ||
          description.contains('serverclientid')) {
        throw const GoogleAccountException(
          'Android needs a Web application OAuth client as its server client. '
          'Create one in Google Cloud Console (type: Web application) and '
          'rebuild with GOOGLE_SERVER_CLIENT_ID set to that client id.',
        );
      }
      if (description.contains('invalid_client') ||
          description.contains('deleted_client')) {
        throw const GoogleAccountException(
          'Google rejected this build\'s client id. Check that the Android '
          'client matches this app\'s package name and signing SHA-1.',
        );
      }
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
      [youtubeWriteScope],
      promptIfNecessary: true,
    );
    if (headers == null) {
      throw const GoogleAuthExpired();
    }
    return headers;
  }
}
