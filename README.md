# TV Passport → XMLTV via GitHub Actions

Automatically grabs the **Spectrum - Manhattan, NY** lineup from TV Passport with WebGrab+Plus and publishes the resulting XMLTV EPG to this repository.

## What it does

1. Uses WebGrab+Plus 5.6.1 Docker.
2. Uses TV Passport's `95433D` lineup ID for **Spectrum - Manhattan, NY**.
3. Runs WebGrab's TV Passport channel-list generation (`c2`) so the repository does **not** contain a manually maintained list of hundreds of channels.
4. Builds a normal WebGrab configuration from the generated channel list.
5. Grabs 7 days of EPG data.
6. Validates the generated XML before committing it.
7. Publishes the result as a GitHub Raw URL.

TV Passport's current New York page lists Spectrum - Manhattan, NY as a provider, and its lineup link currently uses `95433D`.

## EPG URL

After the first successful workflow run:

```text
https://raw.githubusercontent.com/YOUR-USERNAME/YOUR-REPOSITORY/main/output/tvpassport.xml
```

Replace `YOUR-USERNAME/YOUR-REPOSITORY` with your repository path.

## Schedule

The workflow runs twice a day at 00:17 and 12:17 UTC.

You can also start it manually from:

**Actions → Update TV Passport EPG → Run workflow**

## Repository structure

```text
.
├── .github/
│   └── workflows/
│       └── update.yml
├── output/
│   └── tvpassport.xml
└── scripts/
    └── update_epg.sh
```

The WebGrab working directory is created automatically during the Action run and is not committed.

## Important

The workflow intentionally fails instead of committing a suspiciously small/empty EPG.

The previous `output/tvpassport.xml` therefore remains untouched when a grab fails.

## Notes about WebGrab+

The workflow uses the current WebGrab+Plus Docker image documented by the WebGrab+Plus project:

```text
wgmaker/wgpp:latest
```

The project documentation currently describes this Docker image as an early-evaluation build shipping WebGrab+Plus 5.6.1.

TV Passport's official WebGrab siteini is currently old (Revision 0, 2016), but its provider/channel-generation logic still corresponds to the current TV Passport lineup structure. This repository intentionally uses the existing siteini's `c2` channel-generation mechanism rather than hard-coding individual channels.

## Time zone

TV Passport is an America/New_York source. The WebGrab TV Passport siteini uses:

```text
timezone=America/New_York
```

Do **not** change this to Asia/Shanghai. The EPG source timezone should remain the source's actual timezone; the IPTV client can then interpret the XMLTV timestamps appropriately.

## Customization

The main settings are at the top of `scripts/update_epg.sh`:

```bash
LINEUP_ID="95433D"
LINEUP_NAME="Spectrum - Manhattan, NY"
DAYS="7"
```

To use a different TV Passport lineup later, change those values.

## License

This repository contains workflow/configuration glue. WebGrab+Plus and the TV Passport siteini remain subject to their respective licenses/terms.
