# helloporch

Landing page for **Porch**, a tablet plus large-button keypad that lets parents with dementia or limited dexterity start a video call with one press. Implements design 2a from the Claude Design handoff.

## Develop

```sh
npm install
npm run dev
```

## Waitlist

Both forms post to `/api/waitlist`. Every signup is logged to the function logs as JSON (`waitlist_signup`, and `waitlist_who` for the follow-up "who would use Porch?" answer).

To send signups to MailerLite, set these env vars in Vercel:

- `MAILERLITE_API_KEY`: required to enable MailerLite
- `MAILERLITE_GROUP_ID`: optional group to add subscribers to
