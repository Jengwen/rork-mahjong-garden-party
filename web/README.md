# Mahjong Garden Party — Web

Solo Practice in the browser, sharing the iOS app's Supabase project: same login, same `player_profiles` stats/level/settings, same `game_results` history, and one subscription across iPhone (App Store) and web (Stripe).

## Develop

```bash
cd web
npm install
npm run dev            # http://localhost:5173
npm test               # engine tests incl. 300 auto-played games
```

Dev-only preview without signing in: `http://localhost:5173/?preview` (add `&locked` for the paywall, `&auth` for the sign-in screen, `&speed=0.1` for fast bots). It's stripped from production builds.

- `src/engine/` is a port of the iOS solo game: `HandMatcher.swift`, the solo paths of `GameViewModel.swift`, and the tile and card models.
- `src/engine/cards.generated.ts` is generated from `ios/.../NMJLCard2025.swift`. After editing the Swift card, run `python3 web/scripts/convert-card.py`.

## One-time backend setup

1. **Database**: apply `supabase/migrations/20261018_web_entitlements_and_results.sql`. It adds the `user_entitlements` table and the `record_game_result` RPC.
2. **Auth redirect**: in Supabase → Authentication → URL Configuration, add your web URL (e.g. `https://play.mahjonggardenparty.com`) to **Redirect URLs**. Web password resets send people back to it.
3. **Edge functions** (`supabase functions deploy <name>`):

   | Function | JWT verification |
   |---|---|
   | `app-store-sync` | on |
   | `stripe-checkout` | on |
   | `stripe-portal` | on |
   | `app-store-notifications` | **off** (`--no-verify-jwt`) |
   | `stripe-webhook` | **off** (`--no-verify-jwt`) |

4. **Secrets** (`supabase secrets set …`):
   - `WEB_APP_ORIGINS=https://play.mahjonggardenparty.com` (comma-separated; add `http://localhost:5173` for local testing)
   - Apple: `APPLE_IAP_ISSUER_ID`, `APPLE_IAP_KEY_ID`, `APPLE_IAP_PRIVATE_KEY` (the .p8 from App Store Connect → Users and Access → Integrations → In-App Purchase), `APPLE_BUNDLE_ID=com.mahjonggardenparty`
   - Stripe: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_PRICE_MONTHLY` ($1.99/mo price id), `STRIPE_PRICE_ANNUAL` ($19.99/yr price id)
5. **Apple**: App Store Connect → App Information → App Store Server Notifications → V2, Production and Sandbox URL `https://nzfrxpnksrqcqxphtdye.supabase.co/functions/v1/app-store-notifications`.
6. **Stripe**: create the two prices, then add a webhook to `…/functions/v1/stripe-webhook` for `checkout.session.completed` and `customer.subscription.created/updated/deleted`. Turn on the Customer Portal.
7. **iOS**: ship a build containing the `StoreManager` and `AppViewModel` changes, so iPhone subscribers get linked and web subscribers are recognized on the phone.

## Deploy to Namecheap (cPanel)

```bash
npm run build          # outputs web/dist
```

Upload the **contents** of `web/dist` (including `.htaccess`) to the subdomain's document root, e.g. `public_html/play`. Turn on SSL for the subdomain (AutoSSL). The app is a single page, and checkout returns use `?checkout=success`, so no server rewrites are needed.
