# helloporch

Landing page for **Porch**, a tablet plus large-button keypad that lets parents with dementia or limited dexterity start a video call with one press. Implements design 2a from the Claude Design handoff.

## Develop

```sh
npm install
npm run dev
```

## Waitlist

Both forms post to `/api/waitlist`, which adds the email to MailerLite. The follow-up "who would use Porch?" answer is saved to the subscriber's `porch_who` custom field. Each request is also logged to the function logs as JSON (`waitlist_signup` / `waitlist_who`), but Vercel keeps those only briefly, so MailerLite is the record.

Set these env vars in Vercel:

- `MAILERLITE_API_KEY`: required to enable MailerLite
- `MAILERLITE_GROUP_ID`: optional group to add subscribers to
