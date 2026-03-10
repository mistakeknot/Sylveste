Title: My approach to building software with agents

URL Source: https://mistakeknot.substack.com/p/my-approach-to-building-software

Published Time: 2026-02-11T05:17:15+00:00

Markdown Content:
[![Image 1](https://substackcdn.com/image/fetch/$s_!Dwyi!,w_1456,c_limit,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F6bb2ac6a-9c49-4eb7-ad56-4612be54a0f2_2464x1856.png)](https://substackcdn.com/image/fetch/$s_!Dwyi!,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F6bb2ac6a-9c49-4eb7-ad56-4612be54a0f2_2464x1856.png)

Midjourney v7 (Personalized)

> ##### _“The utopian, immanent, and continually frustrated goal of the modern state is to reduce the chaotic, disorderly, constantly changing social reality beneath it to something more closely resembling the administrative grid of its observations.“_
> 
> 
> ##### _— James C. Scott, Seeing Like a State_

As a product manager, I love thinking about how technology can make people’s lives better in ways they don’t expect. This is the most fun part of my job, but like the fun parts of most other jobs, it is something I don’t get to do very often.

I think that’s why I find using agents to build software to be just about the most fun I can have on the computer. Instead of being stuck in endless video meetings, mindlessly reporting progress updates to stakeholders who are looking at another window, I get to think deeply about the problems people face and make things that hopefully improve people’s lives.

Or [silly applications that analyze the orality/literacy of guests to a specific Bloomberg podcast on markets and finance](https://www.onglots.com/).

I have been building software with agents for the last two and a half years (one-fifth as long as I have been building software with humans), first by copying code snippets from Claude.ai's desktop web app into Visual Studio Code, and now by running 20 tmux sessions on a virtual private server across 7 terminal applications. It has been a dizzying experience, given how much the landscape changes in just a month, let alone a year.

Below, I cover my approach to building. I love reading about how other people do this, and I hope this post plays a small role in inspiring others to share their approaches. One of my favorites in this genre of Posting is Peter Steinberger’s “[Just Talk To It - the no-bs Way of Agentic Engineering](https://steipete.me/posts/just-talk-to-it)” from a few months ago. I also learned a lot from Jesse Vincent’s “[Superpowers: How I’m using coding agents in October 2025](https://blog.fsck.com/2025/10/09/superpowers/)”, which covers how he uses his plugin [superpowers](https://github.com/obra/superpowers). Finally, another great guide, published right in the middle of me writing this, is Kieran Klaassen’s [guide to Compound Engineering](https://every.to/guides/compound-engineering), which outlines his approach with his excellent [compound-engineering plugin](https://github.com/EveryInc/compound-engineering-plugin).

Funnily enough, my own approach combines tools from all three of the above developers, who also took the time to write about how they think about building. There’s probably a McLuhan/Ong/Meyrowitz/Scott angle there about how writing both crystallizes and builds the [metis](https://medium.com/@jamestplunkett/metis-matters-6a48270c2731) about whatever one is writing about.

But enough prelude; here is my approach to building software with agents, generalized enough so it’s resilient to changes in specific tools or processes, yet specific enough that you can point Claude Code at it and collaborate with it on finding opportunities for inspiration.

First, I’ll go through my **general guidelines**, then explain how I approach new and existing projects using**agent sprints**,cover **ongoing challenges**, and end with some final thoughts.

*   **Building builds building**

    *   I think this, more than anything else below, is the key takeaway; nothing you read will be more helpful or useful than just Doing The Thing and talking to the agent about what you’re working on and thinking about

    *   Like guitar, you can read all the theory books you want and watch all the YouTube videos out there, but none of that matters as much as applied, active practice

        *   Capability is forged, not absorbed

*   Whenever I write “I do something” in this post, mentally translate that to “I direct Claude Code/Codex CLI/another coding agent to do something”

    *   I wish I could be more specific, but it is very unfun to write “I then direct Claude Code to create this markdown document” hundreds of times in a post

*   The refinement phases are significantly more important than the phases they are refining

    *   Every moment spent refining and reviewing what you are building is worth far more than the actual building itself

    *   A core goal throughout this process is to have no open questions or edge cases for execution phase agents to worry about; just like engineering teams, it is far more expensive to deal with open questions during execution phases than during planning and refinement phases

*   Understand the decisions, tradeoffs, outcomes, and users you are building for, even if you don’t understand the code itself

    *   If you can’t talk about what a given phase or feature is about and how it works, talk to your agent until you can

*   This is going to get repetitive, but it really is that important: talk to the agent about everything, including:

    *   Code or designs you don’t understand

    *   Decisions you’re having trouble making

    *   Skills/plugins you want to adapt for your own workflows

    *   Blindspots and unstated assumptions

*   For a given project, I usually set up two tabs for Claude Code agents; one is for complex plans that require collaborative discussion/investigation, and the other for simpler plans/tasks that can be parallelized

    *   For certain projects that require a lot of tokens for clearly defined work (e.g., reviewing hundreds of game design docs and specs to keep them all updated), I also have a third (or more) tabs for Codex CLI agents

    *   I use separate terminal applications for each project; I currently find it easier to keep track of 7 projects (with at least two of the above tabs) in 7 separate terminal apps than to manage 14 tabs in one terminal window

*   A key part of your work when building with agents is managing/improving their memory files

    *   Update [AGENTS.md](https://agents.md/)/[CLAUDE.md](https://code.claude.com/docs/en/memory#manage-claudes-memory) whenever you find yourself doing something more than once

    *   When using both Claude Code and Codex CLI, update your global CLAUDE.md to point to AGENTS.md

    *   Use a pre-commit hook to add significant updates/decisions to these memory files

*   Build an instinct/intuition (instinctuition?) for what you should parallelize with subagents

    *   Ask your agent to discuss how to understand and cultivate this intuition in a way that makes sense for you

*   Token efficiency is key

    *   One of the most powerful leverage points I have found in this domain is using Claude Code for brainstorming and planning, while having Claude Code orchestrate multiple Codex CLI agents to do the actual implementation and testing

    *   Use pointers in your CLAUDE.md and AGENTS.md files to other memory markdown files to reduce the baseline token burden (e.g., put all your plugin development directions in a plugin-dev.md file and have CLAUDE.md point to it instead of having it all in your CLAUDE.md)

*   Relatedly, evaluate every bit of cognition, interaction, and attention spent on the computer for anything other than building to see if it should be optimized or automated

    *   Tmux is love, Tmux is life; it’s wonderful to be able to work on Claude Code from my laptop and then seamlessly switch to my phone to continue exactly where I left off

    *   Relatedly, I love using [Rectangle](https://rectangleapp.com/) to split all these windows into two-thirds to optimize single window space and multi-window visibility

    *   Learn all the keyboard shortcuts (you can ask your agent to help!) so you can keep your hands on the keyboard as much as possible

        *   Taking your hands off the keyboard to do something is the mindkiller

        *   Rectangle window management and basic operation of your terminal applications (at least New Tab and Close Tab) are particularly helpful to learn

I grappled with what to call the workflow/process below that I use when building software with agents: “workflow” and “process” are so vague and overused that they are useless, while terms like “agentic software development lifecycle” or “agentic developer workflow” sound unhinged.

I ultimately decided on “**agent sprint”**because it’s pithy and clear, and the process actually feels like a sprint. If someone comes up with a better term, let me know, and I would be happy to use something else.

I define an **agent sprint** as the process in which an agent completes a complex task through multiple distinct phases. I do not think it is worth treating agent sprints as concrete, canonical, fixed processes; I find myself continuously iterating on how I run them as I learn about new methods and tools. I do think it is helpful to be as simple as possible and start with how you are already working; trying to stuff your existing workflow into a 17-step framework with ornate, bespoke processes is only going to lead to frustration.

As of 2026/2/10, my **agent sprint** consists of five phases:**Brainstorming**,**Strategy, Planning, Execution**, and**Reflection**, with subphases primarily categorized as either **initial****production** or **subsequent****refinement**. To be clear, I don’t use agent sprints for everything: as models and agents get better, the number of tasks I consider simple enough to do in one shot increases. Additionally, I don’t follow them rigidly; sometimes a plan is refined enough during the brainstorming phase that I don’t need to refine it further.

First, I’ll go over how I run agent sprints for new projects, then for existing projects.

When working on a new project, I like to focus my time, attention, cognition, creativity, and tokens on collaboratively brainstorming with my coding agent through the classic domains of product management: understanding, prioritizing, and specifying the problem, the user, and the critical user journeys they would take to solve that problem. I find it very helpful to brainstorm with Claude Code; Codex CLI is wonderful at engineering review and execution, but tends to lag behind Claude Code on matters of product sense, design, and strategy.

After a few rounds of back-and-forth with Claude Code, I will formalize the above brainstorm conversation into a markdown document under `/docs/brainstorms`. The brainstorm will contain broadly scoped information about vision, goals, target users, and critical user journeys. Once these sections have been roughly sketched out, I will use Claude Code to refine the brainstorm document by identifying and resolving ambiguities, edge cases, and non-goals.

There are a number of tools I like for these refinement phases, but my favorite is [Oracle](https://github.com/steipete/oracle)by [@steipete](https://github.com/steipete). It is funny to me that [OpenClaw](https://github.com/openclaw/openclaw), another one of his creations, has received so much attention; I find `Oracle` to be a far more transformative and interesting tool.

As I mentioned above in the general guidelines, it’s extremely helpful to spend as much time as possible on this phase (and subsequent refinement phases) before building anything, or even before making a plan to build anything.

Once I have finished refining the brainstorm, I’ll create a [product requirements document](https://en.wikipedia.org/wiki/Product_requirements_document) (PRD) based on the brainstorm doc under `/docs/`. This serves as the canonical document/spec that all subsequent documents and agent workflows rely on (and update if needed). There is no canonically correct PRD in terms of what it should cover, but I like these:

*   Vision

*   Problem

*   Users

*   Goals and Non-Goals

*   Features and Requirements

*   Scope and Assumptions

*   Critical User Journeys

For new projects, I focus on making this PRD scoped for an MVP ([minimum viable product](https://en.wikipedia.org/wiki/Minimum_viable_product)). While coding agents make it very easy to build anything, they also make it very easy to build _anything_, which means, without ruthlessly descoping, you can end up in an over-engineered boondoggle no one wants.

In other words, don’t build [the Homer](https://simpsonswiki.com/wiki/The_Homer).

For features that are deprioritized from the MVP, I will create additional phase-1/phase-2/etc PRDs, along with a roadmap that sequences everything. Whenever key decisions are made, I update AGENTS.md and CLAUDE.md (and add a pointer in CLAUDE.md to AGENTS.md) to keep the PRDs and roadmap up to date. The bane of stale specs is ever-present and only gets worse as you add more subagents. [Pre-commit hooks](https://code.claude.com/docs/en/hooks-guide) are a great way to automate the spec and memory refreshes.

Just as with brainstorm refinement, I find that refining the PRD is critical to avoiding the heartache of wasted time and tokens. I don’t move to the next step until I've reviewed and approved every part of the PRD. If there are decisions or considerations I don’t understand, I simply ask my coding agent questions until I feel confident enough to comprehend the tradeoffs and make a decision.

Once I am happy with the initial PRD, I create [beads](https://github.com/steveyegge/beads) and prioritize them; I find `beads` to be an excellent task tracking tool when building with agents. I closely review the priorities with Claude Code, though I need to intervene less and less as time goes on. It has been interesting to see the agent get progressively better at prioritization and analysis as the underlying models improve.

After creating and prioritizing the above beads, I create plan documents based on these beads. Because I spend so much time refining the prior brainstorming and PRD phases, I find these plans require less refinement than when I didn’t (or couldn’t afford to) do such comprehensive refinement phases.

This is where [/flux-drive](https://github.com/mistakeknot/Clavain/blob/main/README.md#reviewing-things-with-flux-drive), a Claude Code command I adapted from the [compound-engineering](https://github.com/EveryInc/compound-engineering-plugin) plugin, really shines. `flux-drive` enables Claude Code to spin up multiple specialized subagents in parallel to take a look at a plan and the codebase through their particular lenses and then provide recommendations to Claude Code in terms of edits/updates to said plan documents and beads.

Depending on the complexity of the beads, I create plans in parallel with subagents and instruct Claude Code to note any critical ambiguities or edge cases in the beads for discussion before we create the plans.

…And yet, I still do a refinement pass on plans because teams of specialized subagents will still find issues and open questions to be resolved via discussion, even at this stage of the process. Fortunately, because so much time and effort have been spent on earlier refinement phases, these questions tend to be quicker.

During this phase, I also ensure that Claude Code determines which, if any, parts of the plan can be parallelized into subagents (this is automatically executed via a skill that kicks off during the plan refinement step to avoid doing it manually each time).

After plans are refined and clarified (and synced back to their parent beads), I finally kick off execution on those plans (or plan, depending on complexity). Execution tends to be the most straightforward part of this process because the plans are clearly and precisely defined; as a result, I don't have to deal with many surprises or issues by this point.

Of course, as agents work to execute this plan, I kick off additional brainstorming, research, and refinement phases to ensure steady progress. I think the dream for many people currently building agent orchestrators is to automate even this higher-level pipeline work, but I find my ability to understand the product, along with my own product management skills, suffers when I hand this off to someone (or something) else.

And at the end of the day, what is the point in automating the fun stuff?

All of the above phases are fun because you get to think deeply about problems and watch things get made, but none of that matters if what is made doesn’t work the way you expect it to. An important part of staying in the loop and spending so much time on refinement and review is to build expectations and definitions of done so that, when the agents complete a plan (or plans), you can easily test outcomes.

Of course, it is critical that the agents follow [test-driven development](https://newsletter.pragmaticengineer.com/p/tdd-ai-agents-and-coding-with-kent) (TDD), but if you are building something for actual users (and/or agents), relying on automated unit, integration, and smoke tests is essential, but not enough. Open a test browser or run a test instance and actually click through to see what, if anything, you and your agents missed. It is very easy to get caught up in the motion and activity of agents working, but that doesn’t actually help you build useful software.

Does the application do what your target user expects it to do? Does it do anything you don’t want it to do? Are there new user interface/experience issues or opportunities to focus on? As always, I like working with Claude Code to verify and validate these findings.

Once I'm satisfied with the work, I create logically grouped commits, push them, and proceed to the compounding step.

Compounding learnings, also adapted from the[compound-engineering](https://github.com/EveryInc/compound-engineering-plugin)plugin, is one of my favorite parts of building with agents. With a single slash command (which I also automate with[stop hooks](https://code.claude.com/docs/en/hooks)), the agent reviews all the gotchas, insights, and lessons from the workflow above and adds them to its memory, making future development even better.

I have found the compounding phase to be critical, especially as a project becomes more complex and bespoke. I also find it helpful to have the agent regularly review the learnings and memory files and consolidate/update/synthesize them to improve its ability to work the way you want and need it to.

After compounding, I begin the agent sprint all over again, building more features and fixing more bugs to push the project forward, bit by bit. While I usually have multiple agent sprints in progress at different stages, I find it helpful to take time between sprints to review where the project stands and what I should do next.

Because the project has so much specific context from all the brainstorming, planning, and refining phases, the beads and roadmap tend to be well prioritized, but there are always new frameworks, technologies, and protocols to explore, especially when building agent-related tools. I think it is useful to regularly set aside intentional, deep-focus time to brainstorm, research, and refine your project roadmaps instead of constantly pushing more agent sprints.

When working on existing projects, the above phases are still very much in play, but there is less initial brainstorming/roadmapping/PRD-crafting involved. Instead, I work with Claude Code to **retrofit** these projects by constructing/updating the essential artifacts in the existing codebase, then reviewing and refining them to build beads from those artifacts and plans from those beads. At that point, I run the same agent sprint, starting at the **Executing Plans**phase.

I also find it helpful to use brainstorming phases and `flux-drive` to challenge core requirements/unstated assumptions in existing projects and find new open source tools/frameworks to address gaps and barriers in the project, especially if the project hasn’t gone through an agent sprint in a while (or ever). Even if it has only been one or two months, I find `flux-drive` to shakes out entirely new, improved approaches to features I was previously stuck on.

“All you need is attention” isn’t just true for [the large language models](https://arxiv.org/abs/1706.03762) powering agents; it’s also critical for humans building with those very same agents. As a result, it’s tragicomically ironic that both focus and attention are incredibly difficult to cultivate in a modern attentional environment supercharged with self-optimizing algorithmic apex predators. Whatever way you can find focus, hold on to it and keep building it.

Relatedly, be careful not to get entranced by agents simply _doing things_. Your projects will always benefit from more of your attention and focus, even as your agents automate more and more of how those projects are developed.

Usage limits are an ongoing concern, but I find that having Claude Code orchestrate Codex subagents, along with using token-efficiency tools like[qmd](https://github.com/tobi/qmd)and my own[tldr-swinton,](https://github.com/mistakeknot/tldr-swinton)makes a big difference in staying within weekly usage units. Additionally, I try to pick the cheapest model I can get away with for subagent tasks; not everything needs Opus 4.6 or even Sonnet 4.5.

Stale docs/memory files are also something I am constantly fighting, although I have added a number of hooks to automate updating these as changes are made. In general, hooks help smooth out many of the rough edges of current coding agents; if you find yourself doing something more than once, ask Claude Code if it should make a hook to automate that thing.

I love building software with agents, and I hope this post helps you have more fun doing the same. As always, I would probably recommend you point your Claude Code (or Codex!) agent at this post, ask it to review it against how you already work, and identify opportunities for improving your own workflow. That is very much how I came up with mine.

If you have questions, recommendations, or feedback, feel free to reach out at [@deanlearner](https://x.com/deanlearner).

> ##### _AI usage disclosure: Along with the image I generated using a personalized model I created in Midjourney v7, I also used Grammarly along with Claude Code for two turns to review the this post for typos/grammatical errors/copy issues. I found Claude Code to be useful for spot checking very basic copy issues; however, it was sadly not impressed by “instinctuation”._
> 
> 
> ##### _Everything else, from first draft to the final version, was all made by me. Pangram, fortunately for my existential dread, [agrees](https://www.pangram.com/history/5e8a9886-fba8-4ae7-9864-7e5524e384d0/?ucc=eR73PIPOPHq). I also used Claude Code to generate the SEO description because in this house, we believe computers should talk to computers._
