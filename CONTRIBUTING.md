# Contributing

By sending a pull request or otherwise contributing to the Everlook addon, you agree to the [CLA](CLA.md). Your contribution becomes the property of Christoffer Hallas.

If you cannot make that assignment, do not contribute. If this is work for an employer, get permission first.

## What gets a second look

A pull request that touches mail, trade, repair, selling, buying, accepting or turning in quests, running text as code (`loadstring`, `setfenv`), secure hooks or state drivers, or a workflow or release script is read with extra care, because Everlook acts for the player and runs inside protected game code. Say in the pull request what it does, when it runs and how a player turns it off. The checks list the added lines that match, in the run summary, so a reviewer sees them first; the list fails nothing. Code from a pull request is read before it is run on a machine that holds a token or a game account.

the Everlook addon is licensed under the [MIT License](LICENSE).
