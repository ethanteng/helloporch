// Makes the admin page's password hash. Run it in a terminal, type the password twice, and save what it prints as
// PORCH_ADMIN_PASSWORD_HASH in the calling project (porch-calling-prototype) in Vercel. The password itself is never
// saved, printed or sent anywhere. Changing the hash later signs out every admin session.
//
//   node scripts/admin-password.mjs
import { checkPassword, hashPassword, maximumPasswordLength, minimumPasswordLength } from '../lib/admin/password.ts';

function ask(prompt) {
  return new Promise((resolve, reject) => {
    if (!process.stdin.isTTY) { reject(new Error('Run this in a terminal, so the password is typed and not shown.')); return; }
    process.stdout.write(prompt);
    const typed = [];
    const finish = () => { process.stdin.off('data', read); process.stdin.setRawMode(false); process.stdin.pause(); process.stdout.write('\n'); };
    const read = text => {
      for (const character of text) {
        if (character === '\r' || character === '\n') { finish(); resolve(typed.join('')); return; }
        if (character === '\u0003') { finish(); reject(new Error('Cancelled.')); return; }
        if (character === '\u007f' || character === '\b') typed.pop(); else typed.push(character);
      }
    };
    process.stdin.setRawMode(true); process.stdin.setEncoding('utf8'); process.stdin.resume(); process.stdin.on('data', read);
  });
}

try {
  const password = await ask(`Admin password (at least ${minimumPasswordLength} characters): `);
  if (password.length < minimumPasswordLength) throw new Error(`Use at least ${minimumPasswordLength} characters. A few unrelated words works well.`);
  if (password.length > maximumPasswordLength) throw new Error(`Use at most ${maximumPasswordLength} characters.`);
  if (await ask('Type it again: ') !== password) throw new Error("The two didn't match. Nothing was made.");
  const hash = await hashPassword(password);
  if (!await checkPassword(password, hash)) throw new Error("The hash didn't check out. Nothing was made.");
  console.log(`\nPORCH_ADMIN_PASSWORD_HASH=${hash}\n`);
  console.log('Add it to the calling project (porch-calling-prototype) in Vercel as a Sensitive environment variable for Production,');
  console.log('with PORCH_ADMIN_ENABLED=1, then redeploy. Keep the password in your password manager: Porch has no way to show it.');
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
