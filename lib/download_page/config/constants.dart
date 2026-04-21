// lib/download_page/config/constants.dart

// OAuth Configuration for HuggingFace
const String hfClientId = '56370c68-410e-4af9-998b-baf53df6cc0c';
const String hfRedirectUri = 'com.tommasogiovannini.gemma://oauthredirect';
const String authEndpoint = 'https://huggingface.co/oauth/authorize';
const String tokenEndpoint = 'https://huggingface.co/oauth/token';
const String scope = 'openid profile read-repos';

// Main Model Configuration (Gemma 4)
//
// The Google source model is the authoritative multimodal Gemma 4 model. The
// LiteRT-LM repository is the mobile package used by the Android runtime.
const String sourceModelRepoId = 'google/gemma-4-E2B-it';
const String sourceModelCardUrl = 'https://huggingface.co/$sourceModelRepoId';
const String modelName = 'gemma-4-E2B-it.litertlm';
const String modelFullName = 'Gemma 4 E2B IT LiteRT-LM';
const String modelRepoId = 'litert-community/gemma-4-E2B-it-litert-lm';
const String modelCardUrl = 'https://huggingface.co/$modelRepoId';
const String downloadUrl =
    '$modelCardUrl/resolve/main/$modelName?download=true';
const int modelExpectedBytes = 2583085056;
const String modelExpectedSha256 =
    'ab7838cdfc8f77e54d8ca45eadceb20452d9f01e4bfade03e5dce27911b27e42';
const String modelRuntime = 'litert_lm';
const String modelCacheSignature =
    '$modelRepoId|$modelName|$modelExpectedBytes|$modelExpectedSha256';

// Native runtime library name expected once the LiteRT-LM Android SDK is wired.
// The app fails during initialization if this runtime is absent instead of
// pretending the downloaded model can run.
const String androidModelRuntimeLib = 'litertlm_jni';

// SharedPreferences Keys
const String downloadStateKey = 'download_state';
const String downloadTaskIdKey = 'download_task_id';
const String downloadedModelSignatureKey = 'downloaded_model_signature';
const String downloadedModelPathKey = 'downloaded_model_path';
const String downloadedModelBytesKey = 'downloaded_model_bytes';
const String downloadedModelModifiedMsKey = 'downloaded_model_modified_ms';
const String authTokenKey = 'auth_token';
const String codeVerifierKey = 'code_verifier';
