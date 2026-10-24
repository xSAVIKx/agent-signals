# Facts

One file per measured fact: `NNN-<slug>.md`, numbered in order. A screen
names the facts that it pins in its `facts` field.

Each fact gives:

1. The date and the agent version that were measured.
2. What was measured, and how.
3. The mechanism: why the agent behaves this way, when it is known.
4. The incident that the fact caused, when there was one.
5. The screens that pin the fact.
6. What was not measured.

A fact that a later version changes stays in the file. Add the new
measurement below it, with its date and version, and mark the old one as
superseded.
