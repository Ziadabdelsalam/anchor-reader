import Foundation

struct Finding: Identifiable {
    let id = UUID()
    let feature: String
    let icon: String
    let evidence: String
    let sources: [(String, String)]
}

enum ResearchContent {
    static let findings: [Finding] = [
        Finding(
            feature: "Small bites, with everything else dimmed",
            icon: "rectangle.center.inset.filled",
            evidence: "When text feels like it blurs together, part of the problem is 'crowding': nearby letters and lines interfere with the one you're looking at. Giving letters more room roughly doubled reading accuracy for children with dyslexia, and helped most those who struggled most. Masking the lines around the one you're reading removes competition for your eyes.",
            sources: [
                ("Zorzi et al. (2012), Extra-large letter spacing improves reading in dyslexia, PNAS", "https://pmc.ncbi.nlm.nih.gov/articles/PMC3396504"),
            ]
        ),
        Finding(
            feature: "Big text by default, and extra letter spacing",
            icon: "textformat.size",
            evidence: "An eye-tracking study of 92 people found larger text and wider character spacing made people read significantly faster, with and without dyslexia. The authors recommend at least 18 pt; in a related study most participants preferred the largest size tested (26 pt). Anchor starts at 24 pt and never goes below 18.",
            sources: [
                ("Rello & Baeza-Yates, How to present more readable text for people with dyslexia (Universitat Pompeu Fabra)", "https://repositori.upf.edu/items/e0ca6f40-a0fa-490f-9d03-53d043270deb"),
            ]
        ),
        Finding(
            feature: "Your font, found by testing",
            icon: "textformat",
            evidence: "Across 352 readers and 16 fonts, the gap between a person's fastest and slowest font was 35%, with no loss of comprehension. No single font was fastest for everyone. That's why the comfort setup times you instead of picking 'the best font' for you.",
            sources: [
                ("Wallace et al. (2022), Towards Individuated Reading Experiences, ACM TOCHI (UCF, Adobe, Google, Brown)", "https://jeffhuang.com/papers/Readability_TOCHI22.pdf"),
            ]
        ),
        Finding(
            feature: "Short sprints, scheduled breaks",
            icon: "timer",
            evidence: "Students who took breaks whenever they felt like it ended up studying in longer stretches, with more fatigue and lower concentration than students on fixed Pomodoro-style breaks. Short 'micro-breaks' reliably increase energy and reduce fatigue. Anchor defaults to 5-minute sprints and lets you finish the bit you're on before the break starts.",
            sources: [
                ("Biwer et al. (2023), Comparing 'Pomodoro' breaks and self-regulated breaks, British Journal of Educational Psychology", "https://cris.maastrichtuniversity.nl/en/publications/understanding-effort-regulation-comparing-pomodoro-breaks-and-sel"),
                ("Albulescu et al. (2022), Micro-breaks meta-analysis, PLOS ONE", "https://doaj.org/article/c6f37b6ba159469296b2cb968b65505f"),
                ("Self-regulated vs Pomodoro vs Flowtime breaks (2025)", "https://pmc.ncbi.nlm.nih.gov/articles/PMC12292963/"),
            ]
        ),
        Finding(
            feature: "Recall checkpoints between sections",
            icon: "brain.head.profile",
            evidence: "Harvard researchers found that short memory tests between segments of an online lecture halved mind-wandering (from about 40% of the time), tripled note-taking and improved retention. A large review rated self-testing as one of the two most effective study techniques; re-reading and highlighting were rated low. In adults with ADHD, prompts that asked readers to check their own understanding closed the comprehension gap with non-ADHD readers.",
            sources: [
                ("Szpunar, Khan & Schacter (2013), Interpolated memory tests reduce mind wandering, PNAS", "https://pmc.ncbi.nlm.nih.gov/articles/PMC3631699/"),
                ("Dunlosky et al. (2013), Improving Students' Learning With Effective Learning Techniques", "https://www.sciencedaily.com/releases/2013/01/130110111734.htm"),
                ("Metacognitive scaffolding for digital reading and mind wandering in adults with ADHD", "https://cris.openu.ac.il/en/publications/metacognitive-scaffolding-for-digital-reading-and-mind-wandering-/"),
                ("Eye-Mind Reader: self-explanation when mind-wandering is detected", "https://experts.umn.edu/en/publications/eye-mind-reader-an-intelligent-reading-interface-that-promotes-lo/"),
            ]
        ),
        Finding(
            feature: "The “zoned out” key and gentle nudges",
            icon: "arrow.uturn.backward",
            evidence: "People with more ADHD symptoms mind-wander more, especially on unengaging text, and are less likely to notice when it happens. Pressing D when you catch yourself drifting trains that noticing, and steps you back so nothing is lost. If you stall on one bit for much longer than your usual pace, Anchor asks if you're still with it.",
            sources: [
                ("University of Waterloo: mind-wandering, ADHD, engagingness and effort", "https://uwspace.uwaterloo.ca/items/b6000f50-3ae8-4613-a6eb-19002513f983"),
                ("ADD.org: ADHD, mind wandering and meta-awareness", "https://add.org/coaches-corner-adhd-mind-wandering-and-meta-awareness-what-the-research-says/"),
            ]
        ),
        Finding(
            feature: "Read aloud with word highlighting",
            icon: "speaker.wave.2",
            evidence: "In an eye-tracking study, text-to-speech significantly improved comprehension for students with ADHD-related reading difficulties, and reduced reading time and effort for students with dyslexia while keeping comprehension the same.",
            sources: [
                ("The effects of text-to-speech on reading comprehension (National Taiwan Normal University)", "https://scholar.lib.ntnu.edu.tw/en/publications/the-effects-of-text-to-speech-on-reading-comprehension-in-junior-/"),
            ]
        ),
        Finding(
            feature: "Dark text on light background by default",
            icon: "sun.max",
            evidence: "Proofreading is more accurate with dark text on a light background, likely because the brighter screen narrows the pupil and sharpens the image. The Night theme is there for evenings, but Paper is the default.",
            sources: [
                ("Piepenbrock et al., the positive polarity advantage (Ergonomics), summarized by cogsci.nl", "https://cogsci.nl/blog/is-bright-text-on-a-dark-background-a-good-idea"),
            ]
        ),
        Finding(
            feature: "A moderate line width",
            icon: "arrow.left.and.right",
            evidence: "People can skim long lines quickly but consistently prefer about 45 to 72 characters per line. Anchor starts at 60 and lets you change it.",
            sources: [
                ("Dyson & Kipping on line length for on-screen reading (Human Factors International summary)", "https://humanfactors.com/newsletters/optimal_line_length.html"),
            ]
        ),
        Finding(
            feature: "Phone out of the room",
            icon: "iphone.slash",
            evidence: "In experiments with about 800 people, having your own phone on the desk, even face-down and silent, reduced available working memory. People whose phones were in another room did best.",
            sources: [
                ("Ward et al. (2017), Brain Drain, University of Texas at Austin", "https://news.utexas.edu/2017/06/26/the-mere-presence-of-your-smartphone-reduces-brain-power"),
            ]
        ),
        Finding(
            feature: "Timer pauses when you switch apps, plus a “welcome back”",
            icon: "arrow.uturn.left.circle",
            evidence: "Gloria Mark's research at UC Irvine finds attention on any one screen now lasts about 47 seconds on average, and getting back to a task after an interruption can take close to half an hour. Anchor pauses the sprint when you leave and shows you exactly where you were when you return.",
            sources: [
                ("UC Irvine / University of California: How to sharpen your attention", "https://www.universityofcalifornia.edu/news/how-sharpen-your-attention-and-meet-your-goals-2024"),
            ]
        ),
        Finding(
            feature: "You set the pace: no auto-scrolling",
            icon: "hand.raised",
            evidence: "Speed-reading apps that flash one word at a time take away your control over eye movements, including the small look-backs that support comprehension. Understanding drops as speed rises. In Anchor, nothing moves until you press Space.",
            sources: [
                ("Rayner et al. (2016), So much to read, so little time, Psychological Science in the Public Interest", "https://profiles.wustl.edu/en/publications/so-much-to-read-so-little-time-how-do-we-read-and-can-speed-readi/"),
            ]
        ),
    ]

    static let leftOut: [Finding] = [
        Finding(
            feature: "Bionic Reading (bolded word starts)",
            icon: "bold",
            evidence: "A test with 2,074 readers found no speed benefit, and a peer-reviewed 2024 study found no difference in reading times. Not included.",
            sources: [
                ("Readwise: we timed over 2,000 readers", "https://blog.readwise.io/bionic-reading-results/"),
                ("No, Bionic Reading does not work (VU Amsterdam)", "https://research.vu.nl/en/publications/no-bionic-reading-does-not-work/"),
            ]
        ),
        Finding(
            feature: "Colored overlays as a treatment",
            icon: "paintpalette",
            evidence: "A systematic review of 51 studies concluded coloured overlays and lenses can't be endorsed for reading difficulties. Anchor offers tints only as a comfort preference, not as a fix.",
            sources: [
                ("Griffiths et al. (2016), Ophthalmic & Physiological Optics", "https://eprints.whiterose.ac.uk/104441/"),
            ]
        ),
        Finding(
            feature: "Speed reading (RSVP, word flashing)",
            icon: "hare",
            evidence: "Trades understanding for speed. See “You set the pace” above.",
            sources: [
                ("Modern speed reading apps do not foster reading comprehension", "https://scholarlypublishingcollective.org/uip/ajp/article/130/2/183/258180/Modern-Speed-Reading-Apps-Do-Not-Foster-Reading"),
            ]
        ),
    ]

    static let tips: [String] = [
        "For a document that really matters, consider printing it. A meta-analysis of 54 studies found comprehension of informational text is a bit better on paper, especially under time pressure.",
        "Skim the headings first (press O). Knowing the shape of a document gives new information somewhere to land.",
        "Read with a question in mind: “what do I need from this?” It turns passive reading into a search.",
        "Stop on purpose, before you're exhausted. Ending a sprint while it still feels doable makes the next one easier to start.",
        "Notice when you've drifted, and come back without scolding yourself. Noticing is the skill.",
        "Spread long documents over several short sessions instead of one marathon. Spaced practice was one of the two highest-rated techniques in the Dunlosky review.",
    ]

    static let paperVsScreen = ("Delgado et al. (2018), Don't throw away your printed books, Educational Research Review", "https://www.uv.es/lasalgon/papers/Delgado%202018%20dont%20throw%20away%20your%20printed%20books.pdf")
}
