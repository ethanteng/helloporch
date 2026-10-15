# helloporch

Landing page for **Porch**, a tablet plus large-button keypad that lets individuals with dementia or limited dexterity start a video call with one press. Implements design 3a from the Claude Design handoff.

## Develop

The native iPad FaceTime/keypad prototype lives in [`ios/`](ios/README.md). Open `ios/Porch.xcodeproj` in Xcode. Native build and TestFlight workflows are included alongside this landing page.

```sh
npm install
npm run dev
```

## Waitlist

Both forms post to `/api/waitlist`, which adds the email to MailerLite. The follow-up "who would use Porch?" answer is saved to the subscriber's `porch_who` custom field. Each request is also logged to the function logs as JSON (`waitlist_signup` / `waitlist_who`), but Vercel keeps those only briefly, so MailerLite is the record.

Set these env vars in Vercel:

- `MAILERLITE_API_KEY`: required to enable MailerLite
- `MAILERLITE_GROUP_ID`: optional group to add subscribers to

## Demo video

The demo video defaults to the v2 file on Vercel Blob. To use a different one, set `NEXT_PUBLIC_DEMO_VIDEO_URL` in Vercel to the new `.mp4` URL and redeploy. The value is built into the page, so changing it has no effect until the next deployment.
