# Server and TestFlight releases

Pull requests run calling-server checks and the iPhone/iPad build workflow. Relevant server changes merged to `main` also run **Deploy calling server**. TestFlight uploads stay manual: choose **Upload Porch to TestFlight → Run workflow → main** when changes are ready for family testing.

The TestFlight workflow first calls the same server release workflow for its exact commit. Server tests, TypeScript checks, and a production build must pass before deployment. CI then builds with the calling project's production configuration, stages a production deployment without moving the live address, and checks `/api/calls/health` for the expected commit, calling configuration, reachable shared storage, and APNs configuration. It promotes that deployment and checks the address used by the iPad again. Only then can the signed app upload start. A failed check or deploy stops the upload. These checks never dial a phone or join media; real-device push and audio testing is still needed.

For a deliberate test of unmerged work, manually select its reviewed branch in the release workflow. This also updates the real calling server; ordinary PR pushes only run checks and create the existing website preview. An app-only release still verifies/deploys its matching server commit, so the release cannot silently depend on an older backend.

## One-time GitHub setup

In this repository's **Settings → Environments**, create **calling-server-production** and add the environment secret **VERCEL_TOKEN**. Create the token in Vercel's account token settings with access to **ethan-teng-consulting-llc**. Enter its value directly in GitHub; never put it in chat, a workflow file, or Git.

An existing repository Actions secret named `VERCEL_TOKEN` also works: the TestFlight caller passes this one secret explicitly to the reusable workflow. A secret in `calling-server-production` takes precedence. Secrets in a different environment, including `testflight`, are unavailable to the server job; GitHub Actions variables are not secrets.

The workflow already pins the existing calling target:

- Team: `team_xLXDpIOs1pK3jkr6PExoAET8` (`ethan-teng-consulting-llc`).
- Project: `prj_1m03AHibL90MRxlExgzujzYlSix6` (`porch-calling-prototype`).
- Live address: `https://porch-calling-prototype.vercel.app`.

It verifies the linked project's name and IDs before building. This target is separate from the `helloporch` website project. Keep Redis, LiveKit, APNs, and telephone credentials in the existing calling project's Vercel production environment; they do not need to be copied into GitHub.

Staged health checks use authenticated `vercel curl` with the same CI token, so Vercel Deployment Protection can stay enabled without a second bypass secret. The script restricts authenticated requests to a Vercel health endpoint and does not pass tokens as command arguments or follow redirects. After promotion it checks the live address without Vercel authentication, just as the native app uses it.

Vercel credentials are exposed only to the CLI steps that need them. The workflow pins its CLI and action versions, does not upload pulled environment files or build output as artifacts, and deletes `.vercel` on completion. Use GitHub's existing repository and environment controls to limit who can run production releases.

## Retry and recovery

After setting the secret, run **Deploy calling server** on the intended reviewed commit. This can release the server independently, including after an app has already been uploaded. Once this workflow is on `main`, it also runs automatically for relevant merges.

The job summary records the live address, unique deployment URL, and commit. Check the commit and failure step before retrying. A staging failure leaves the previous server live. If a post-promotion check fails, the upload stays blocked; inspect the production deployment and use Vercel's rollback control if needed. No database schema changes or provider-routing changes are performed by this workflow.
