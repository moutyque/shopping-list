# Release pipeline — one-time setup

Pushing/merging to `master` runs `.github/workflows/release.yml`, which analyzes,
tests, builds a **signed release APK**, and attaches it to a GitHub Release. Each
run's number becomes the Android `versionCode`, so a newer build installs over an
older one on your phone.

You only do the steps below **once**.

## 1. Create the repo and push (if not done yet)

```bash
cd ~/IdeaProjects/shopping-list
gh repo create shopping-list --private --source=. --remote=origin
git push -u origin master
```

## 2. Generate a release keystore (keep it safe — losing it means you can't update the app)

```bash
keytool -genkey -v \
  -keystore ~/shopping-list-release.jks \
  -alias shopping-list \
  -keyalg RSA -keysize 2048 -validity 10000
```

Pick a store password and a key password (they can be the same). Remember them.

## 3. Add the four GitHub secrets

```bash
# base64-encode the keystore so it can live in a secret
base64 -i ~/shopping-list-release.jks | gh secret set KEYSTORE_BASE64

gh secret set KEYSTORE_PASSWORD   # the store password from step 2
gh secret set KEY_ALIAS           # value: shopping-list
gh secret set KEY_PASSWORD        # the key password from step 2
```

## 4. Trigger it

Push anything to `master` (or run the workflow manually from the **Actions** tab).
When it finishes, grab the APK from the repo's **Releases** page and install it on
your phone.

## 5. Firebase App Distribution (deliver to testers)

The workflow uploads each build to Firebase App Distribution **only once
`FIREBASE_APP_ID` is set** — until then that step is skipped and the GitHub
Release still publishes, so master stays green.

### a. Create the Firebase project + Android app

1. Go to <https://console.firebase.google.com> → **Add project** (free; you can
   skip Google Analytics).
2. In the project, **Add app → Android**. Use package name
   `com.qmouty.shopping_list`. You can skip downloading `google-services.json`
   (the app doesn't use Firebase SDKs — only distribution).
3. Copy the **App ID** shown for the app — it looks like
   `1:1234567890:android:abc123…`.

### b. Enable App Distribution + create a tester group

1. Left menu → **Run → App Distribution** → **Get started**.
2. Open the **Testers & Groups** tab → create a group with alias **`internal`**
   (must match `groups: internal` in the workflow) → add your tester emails
   (yours, family, etc.).

### c. Create a service account for CI

1. Google Cloud Console → **IAM & Admin → Service Accounts**
   (<https://console.cloud.google.com/iam-admin/serviceaccounts>), same project.
2. **Create service account** (e.g. `ci-app-distribution`).
3. Grant it the role **Firebase App Distribution Admin**.
4. Open it → **Keys → Add key → Create new key → JSON** → download the file.

### d. Add the two GitHub secrets

```bash
gh secret set FIREBASE_APP_ID            # paste the App ID from step a.3
gh secret set FIREBASE_SERVICE_ACCOUNT < ~/Downloads/<that-key>.json
```

### e. First run

Push to `master`. Testers in the `internal` group get an email; they install the
**Firebase App Tester** app once, then receive each new build as a notification.

## Local signed builds (optional)

To build a signed APK locally, create `android/key.properties` (git-ignored):

```properties
storeFile=/absolute/path/to/shopping-list-release.jks
storePassword=...
keyAlias=shopping-list
keyPassword=...
```

Without that file, `flutter build apk --release` falls back to the debug key —
fine for local testing, but those APKs can't update over a CI-signed one.

## Not covered

- **iOS**: needs full Xcode + an Apple signing team; can't be built in this setup.
- **Play Store**: this publishes a sideloadable APK, not a Play listing.
