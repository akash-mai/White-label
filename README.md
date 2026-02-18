# 🚀 White-Label Mobile App Automation System

Automated rebranding and build pipeline for Flutter apps, using **Node.js**, **AWS**, **GitHub Actions**, and **Fastlane**.

## 🏗 System Architecture

1.  **Frontend (Next.js)**: User Interface to upload assets (Logo, Splash) and configuration (Apple/Firebase keys).
2.  **Backend (Node.js)**: Validates requests, stores assets in **AWS S3**, manages keystores securely, and triggers **GitHub Actions**.
3.  **CI/CD (GitHub Actions)**:
    *   Fetches secrets from **AWS Secrets Manager**.
    *   Downloads assets from **S3**.
    *   Updates Flutter project settings (Package Name, Bundle ID, Assets).
    *   **Fastlane**: Syncs iOS certificates/profiles from a private git repo.
    *   Builds signed **Android APK** and **iOS IPA**.
    *   Uploads artifacts.

---

## 🛠 Prerequisites

### 1. AWS Account
*   Create an **IAM User** with programmatic access (Access Key ID & Secret Access Key).
*   Create an **S3 Bucket** (e.g., `my-white-label-assets`).
*   **Permissions**: The IAM user needs `S3` (Read/Write) and `SecretsManager` (Read/Write) access.

### 2. Apple Developer Account
*   **App Store Connect API Key** (`.p8` file).
*   **Issuer ID** and **Key ID**.

### 3. Private Git Repo (for Fastlane Match)
*   Create a separate, empty private repository (e.g., `ios-certificates`) to store encrypted certificates.
*   Create a strong **Match Password** (passphrase) to encrypt this repo.

---

## ⚙️ Setup Guide (For a New Environment)

### 1. Clone & Configure this Repository
Clone this repo to your local machine or fork it to your GitHub account.

### 2. Configure Backend Credentials
Create a `.env` file in `white-label-backend/`:

```bash
# AWS Credentials
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
AWS_REGION=ap-south-1  # Verify this matches your S3/SecretsManager region
S3_BUCKET=your-s3-bucket-name

# GitHub Integration (To trigger the workflow)
GH_PAT=your_github_personal_access_token # Needs 'repo' scope
GH_OWNER=your_github_username
GH_REPO=your_repo_name

# Security
INTERNAL_API_KEY=generate_random_string_here # Use: openssl rand -hex 32
```

### 3. Configure Frontend Credentials
Create a `.env.local` file in `white-label-frontend/`:

```bash
NEXT_PUBLIC_INTERNAL_API_KEY=same_string_as_backend
NEXT_PUBLIC_API_URL=http://localhost:3000
```

### 4. Configure GitHub Repository Secrets
Go to your **GitHub Repo -> Settings -> Secrets and variables -> Actions**. Add the following:

| Secret Name | Value |
|---|---|
| `AWS_KEY` | Your AWS Access Key ID |
| `AWS_SECRET` | Your AWS Secret Access Key |
| `S3_BUCKET` | Your S3 Bucket Name |
| `MATCH_GIT_URL` | URL to your Private Cert Repo (e.g., `https://github.com/user/certs.git`) |
| `MATCH_PASSWORD` | The passphrase you chose to encrypt the cert repo |

> **Note**: `rebrand.yml` is configured for `ap-south-1` region. if you use a different region, **Edit `.github/workflows/rebrand.yml`** and update `aws-region`.

---

## 🚀 Usage (Local Development)

### 1. Start the Backend
```bash
cd white-label-backend
npm install
node server.js
# Server runs on http://localhost:3000
```

### 2. Start the Frontend
```bash
cd white-label-frontend
npm install
npm run dev
# Frontend runs on http://localhost:3001
```

### 3. Trigger a Build
1.  Open the frontend (http://localhost:3001).
2.  Enter **App Name** and **Bundle ID**.
3.  Upload **Logo** and **Splash Screen**.
4.  (Optional) Upload **Firebase Configs** (`google-services.json`, `GoogleService-Info.plist`).
5.  (Optional) Enter **Apple Credentials** (Team ID, Issuer ID, Key ID, .p8 file).
    *   *If Apple details are omitted, the iOS build and Fastlane steps are automatically skipped.*
6.  Click **Start Build**.

This will:
*   Upload assets to S3.
*   Generate/Reuse Android Keystore (Password stored in AWS Secrets Manager).
*   Trigger the GitHub Action.
*   **Result**: Signed APK (and IPA) uploaded to GitHub Artifacts.

---

## 🔍 Troubleshooting

*   **Secret Not Found (ResourceNotFoundException)**:
    *   Ensure `AWS_REGION` in `.env` matches `aws-region` in `.github/workflows/rebrand.yml`.
    *   The backend validates existing secrets and **auto-regenerates** a new keystore if the secret is missing.
*   **Fastlane/iOS Failures**:
    *   Ensure `MATCH_GIT_URL` is correct and accessible by the GitHub Runner.
    *   Ensure the Apple API Key is valid.
    *   If you don't need iOS, simply leave the Apple fields blank in the UI.

## 📂 Project Structure

*   `white-label-backend/`: Node.js API.
*   `white-label-frontend/`: Next.js Dashboard.
*   `white_label_mobile/`: Flutter App Source.
    *   `rebrand_cli/`: Dart CLI tool that injects assets and updates native files.
    *   `.github/workflows/rebrand.yml`: CI/CD Pipeline definition.
