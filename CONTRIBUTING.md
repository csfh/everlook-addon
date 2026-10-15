# Contributing

By sending a pull request or otherwise contributing to the Everlook addon, you agree to the [CLA](CLA.md). Your contribution becomes the property of Christoffer Hallas.

If you cannot make that assignment, do not contribute. If this is work for an employer, get permission first.

## What gets a second look

A pull request that touches mail, trade, repair, selling, buying, accepting or turning in quests, running text as code (`loadstring`, `setfenv`), secure hooks or state drivers, or a workflow or release script is read with extra care, because Everlook acts for the player and runs inside protected game code. Say in the pull request what it does, when it runs and how a player turns it off. The checks list the added lines that match, in the run summary, so a reviewer sees them first; the list fails nothing. Code from a pull request is read before it is run on a machine that holds a token or a game account.

## How reports are handled

A report is answered with one of four things: a question when something needed to reproduce it is missing, a confirmation, a fix in `main`, or a closing note that gives the reason. A fix names the person who reported it in a `Reported-by: <name>` line in the commit body, and the release notes thank everyone named that way. Fixes go to `main` as soon as they are ready, so a contributor does not rewrite what is already done there. Check recent commits before starting work on a report.

the Everlook addon is licensed under the [MIT License](LICENSE).
