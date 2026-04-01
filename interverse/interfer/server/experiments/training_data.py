"""Training data generator for reservoir routing.

Generates labeled prompt examples for each routing class and produces
train/test splits in JSONL format.
"""

from __future__ import annotations

import json
import random
from pathlib import Path
from typing import Literal

from .reservoir_routing import CLASS_LABELS

# Template pools for diverse prompt generation.
_CODING_SUBJECTS = [
    "sorting algorithm",
    "binary search tree",
    "REST API endpoint",
    "database migration",
    "unit test",
    "CLI tool",
    "web scraper",
    "auth middleware",
    "caching layer",
    "rate limiter",
    "logging system",
    "config parser",
    "file watcher",
    "CSV parser",
    "HTTP client",
    "WebSocket handler",
    "queue consumer",
    "batch processor",
    "data pipeline",
    "graph traversal",
    "hash map",
    "linked list",
    "thread pool",
    "connection pool",
    "retry mechanism",
    "circuit breaker",
    "load balancer",
    "dependency injector",
    "event emitter",
    "state machine",
]

_CODING_LANGUAGES = [
    "Python",
    "Go",
    "Rust",
    "TypeScript",
    "JavaScript",
    "Java",
    "C++",
    "Swift",
]

_CODING_TEMPLATES = [
    "Write a {lang} function that implements a {subject}",
    "How do I create a {subject} in {lang}?",
    "Debug this {lang} code for a {subject}: it returns the wrong result",
    "Refactor this {subject} implementation to be more efficient in {lang}",
    "Write tests for a {subject} in {lang}",
    "Implement a {subject} that handles edge cases in {lang}",
    "Convert this {subject} from Python to {lang}",
    "Optimize the memory usage of this {subject} in {lang}",
]

_REASONING_TOPICS = [
    "climate change impacts",
    "quantum computing applications",
    "economic policy",
    "machine learning bias",
    "space exploration funding",
    "education reform",
    "healthcare systems",
    "energy transitions",
    "urban planning",
    "food security",
    "AI governance",
    "cybersecurity threats",
    "demographic shifts",
    "trade policy",
    "biodiversity loss",
    "transportation infrastructure",
    "housing affordability",
    "water scarcity",
    "digital privacy",
    "labor market automation",
]

_REASONING_TEMPLATES = [
    "Analyze the trade-offs between {topic_a} and {topic_b}",
    "What are the second-order effects of changes in {topic}?",
    "Compare and contrast three approaches to {topic}",
    "If {topic} trends continue for 20 years, what happens?",
    "Explain the causal chain from {topic_a} to {topic_b}",
    "What are the strongest counterarguments to the mainstream view on {topic}?",
    "Design a framework for evaluating proposals related to {topic}",
    "What assumptions does the standard model of {topic} rely on?",
]

_CREATIVE_GENRES = [
    "science fiction",
    "fantasy",
    "mystery",
    "romance",
    "horror",
    "literary fiction",
    "historical fiction",
    "thriller",
    "comedy",
    "dystopian",
    "magical realism",
]

_CREATIVE_ELEMENTS = [
    "an unreliable narrator",
    "a twist ending",
    "parallel timelines",
    "a morally ambiguous protagonist",
    "epistolary format",
    "second-person perspective",
    "stream of consciousness",
    "an ensemble cast",
    "a framing device",
    "non-linear chronology",
    "a story within a story",
]

_CREATIVE_TEMPLATES = [
    "Write a {genre} short story featuring {element}",
    "Create a poem about {topic} in the style of {genre}",
    "Write the opening chapter of a {genre} novel with {element}",
    "Compose a dialogue between two characters debating {topic} in a {genre} setting",
    "Write a {genre} flash fiction piece (under 500 words) about {topic}",
    "Create a monologue for a character in a {genre} story dealing with {topic}",
    "Write a {genre} scene that uses {element} to explore {topic}",
]

_FACTUAL_DOMAINS = [
    "history",
    "biology",
    "physics",
    "chemistry",
    "mathematics",
    "astronomy",
    "geology",
    "psychology",
    "sociology",
    "economics",
    "linguistics",
    "philosophy",
    "computer science",
    "medicine",
    "engineering",
    "ecology",
    "anthropology",
]

_FACTUAL_SPECIFICS = {
    "history": [
        "the Roman Empire",
        "World War II",
        "the Industrial Revolution",
        "the Ming Dynasty",
        "the French Revolution",
    ],
    "biology": [
        "photosynthesis",
        "DNA replication",
        "immune response",
        "evolution by natural selection",
        "cell mitosis",
    ],
    "physics": [
        "quantum entanglement",
        "general relativity",
        "thermodynamics",
        "electromagnetic induction",
        "wave-particle duality",
    ],
    "chemistry": [
        "covalent bonding",
        "redox reactions",
        "organic synthesis",
        "catalysis",
        "polymer chemistry",
    ],
    "mathematics": [
        "the Riemann hypothesis",
        "group theory",
        "topology",
        "Bayesian inference",
        "differential equations",
    ],
    "astronomy": [
        "black holes",
        "neutron stars",
        "the cosmic microwave background",
        "exoplanet detection",
        "dark matter",
    ],
}

_FACTUAL_TEMPLATES = [
    "Explain {specific} in simple terms",
    "What is the current scientific consensus on {specific}?",
    "How was {specific} discovered and what impact did it have?",
    "Summarize the key principles of {domain} related to {specific}",
    "What are common misconceptions about {specific}?",
    "How does {specific} relate to everyday life?",
    "What are the latest developments in {domain} regarding {specific}?",
]

# Templates for 3-class scheme (small/medium/large)
_SMALL_TEMPLATES = [
    "What is {thing}?",
    "Define {thing}",
    "Hello, how are you?",
    "Hi there!",
    "What time is it in {city}?",
    "What's the capital of {country}?",
    "Translate '{phrase}' to {language}",
    "How do you say '{phrase}' in {language}?",
    "What's the weather like?",
    "Who invented {thing}?",
    "When was {thing} invented?",
    "What color is {thing}?",
    "How many {thing} are there?",
    "Yes or no: is {thing} true?",
    "Thanks!",
    "OK",
]

_SMALL_THINGS = [
    "a CPU",
    "the internet",
    "photosynthesis",
    "gravity",
    "an API",
    "a database",
    "machine learning",
    "a compiler",
    "TCP/IP",
    "encryption",
    "the moon",
    "a transistor",
    "HTTP",
    "DNA",
    "a neural network",
]

_SMALL_CITIES = [
    "Tokyo",
    "London",
    "New York",
    "Sydney",
    "Mumbai",
    "Berlin",
    "São Paulo",
]
_SMALL_COUNTRIES = [
    "France",
    "Japan",
    "Brazil",
    "Egypt",
    "Canada",
    "Australia",
    "Nigeria",
]
_SMALL_PHRASES = [
    "good morning",
    "thank you",
    "I love you",
    "where is the library",
    "how much does it cost",
]
_SMALL_LANGUAGES = [
    "Spanish",
    "French",
    "Japanese",
    "German",
    "Mandarin",
    "Arabic",
    "Portuguese",
]

_MEDIUM_TEMPLATES = [
    "Write a Python function to {task}",
    "Explain the difference between {a} and {b}",
    "How do I set up {tool} for a new project?",
    "Debug this error: {error}",
    "What are best practices for {practice}?",
    "Summarize the key points of {topic}",
    "Create a SQL query that {task}",
    "Design a data model for {domain}",
]

_MEDIUM_TASKS = [
    "sort a list of dictionaries by a key",
    "parse JSON from an API response",
    "implement a binary search",
    "validate an email address",
    "read a CSV file and compute averages",
    "connect to a PostgreSQL database",
    "implement rate limiting",
    "handle file uploads",
]

_LARGE_TEMPLATES = [
    "Write a comprehensive guide to building a {project} from scratch",
    "Design the architecture for a {system} that handles {scale}",
    "Create a detailed comparison of {options} for {use_case}, including benchmarks and trade-offs",
    "Write a {genre} story exploring the theme of {theme} across three interconnected narratives",
    "Develop a curriculum for teaching {subject} to {audience} over {duration}",
    "Analyze the geopolitical implications of {event} on {regions} over the next decade",
]


def generate_training_data(
    num_per_class: int = 200,
    seed: int = 42,
    label_scheme: Literal["3class", "4class"] = "3class",
) -> list[dict]:
    """Generate labeled prompt examples for reservoir routing training.

    Args:
        num_per_class: Number of prompts to generate per class.
        seed: Random seed for reproducibility.
        label_scheme: Either "3class" (small/medium/large) or "4class" (coding/reasoning/creative/factual).

    Returns:
        List of dicts with keys: prompt, label, label_id.

    Raises:
        ValueError: If num_per_class < 1 or label_scheme is invalid.
    """
    if num_per_class < 1:
        raise ValueError(f"num_per_class must be >= 1, got {num_per_class}")
    if label_scheme not in CLASS_LABELS:
        raise ValueError(
            f"Unknown label_scheme {label_scheme!r}. Choose from: {list(CLASS_LABELS)}"
        )

    rng = random.Random(seed)
    labels = CLASS_LABELS[label_scheme]
    data: list[dict] = []

    for label_id, label in enumerate(labels):
        for _ in range(num_per_class):
            prompt = _generate_prompt(label, label_scheme, rng)
            data.append({"prompt": prompt, "label": label, "label_id": label_id})

    rng.shuffle(data)
    return data


def _generate_prompt(label: str, scheme: str, rng: random.Random) -> str:
    """Generate a single prompt for the given label and scheme."""
    if scheme == "4class":
        return _generate_4class_prompt(label, rng)
    return _generate_3class_prompt(label, rng)


def _generate_4class_prompt(label: str, rng: random.Random) -> str:
    if label == "coding":
        tpl = rng.choice(_CODING_TEMPLATES)
        return tpl.format(
            lang=rng.choice(_CODING_LANGUAGES), subject=rng.choice(_CODING_SUBJECTS)
        )
    elif label == "reasoning":
        tpl = rng.choice(_REASONING_TEMPLATES)
        topics = rng.sample(_REASONING_TOPICS, min(2, len(_REASONING_TOPICS)))
        return tpl.format(topic=topics[0], topic_a=topics[0], topic_b=topics[-1])
    elif label == "creative":
        tpl = rng.choice(_CREATIVE_TEMPLATES)
        return tpl.format(
            genre=rng.choice(_CREATIVE_GENRES),
            element=rng.choice(_CREATIVE_ELEMENTS),
            topic=rng.choice(_REASONING_TOPICS),
        )
    else:  # factual
        tpl = rng.choice(_FACTUAL_TEMPLATES)
        domain = rng.choice(list(_FACTUAL_SPECIFICS.keys()))
        specific = rng.choice(_FACTUAL_SPECIFICS[domain])
        return tpl.format(domain=domain, specific=specific)


def _generate_3class_prompt(label: str, rng: random.Random) -> str:
    if label == "small":
        tpl = rng.choice(_SMALL_TEMPLATES)
        return tpl.format(
            thing=rng.choice(_SMALL_THINGS),
            city=rng.choice(_SMALL_CITIES),
            country=rng.choice(_SMALL_COUNTRIES),
            phrase=rng.choice(_SMALL_PHRASES),
            language=rng.choice(_SMALL_LANGUAGES),
        )
    elif label == "medium":
        tpl = rng.choice(_MEDIUM_TEMPLATES)
        return tpl.format(
            task=rng.choice(_MEDIUM_TASKS),
            a="async and sync programming",
            b="threads and coroutines",
            tool=rng.choice(
                ["Docker", "Kubernetes", "Terraform", "GitHub Actions", "Vercel"]
            ),
            error=rng.choice(
                [
                    "ModuleNotFoundError",
                    "ConnectionTimeout",
                    "PermissionDenied",
                    "OutOfMemory",
                ]
            ),
            practice=rng.choice(
                ["error handling", "API design", "database indexing", "caching"]
            ),
            topic=rng.choice(_REASONING_TOPICS),
            domain=rng.choice(
                ["e-commerce", "social media", "healthcare", "logistics"]
            ),
        )
    else:  # large
        tpl = rng.choice(_LARGE_TEMPLATES)
        return tpl.format(
            project=rng.choice(
                [
                    "distributed cache",
                    "search engine",
                    "real-time chat system",
                    "CI/CD pipeline",
                ]
            ),
            system=rng.choice(
                ["microservices platform", "data pipeline", "content delivery network"]
            ),
            scale=rng.choice(
                ["10M daily users", "1TB/day data ingestion", "sub-10ms latency"]
            ),
            options=rng.choice(
                [
                    "PostgreSQL vs DynamoDB vs CockroachDB",
                    "Kafka vs RabbitMQ vs Redis Streams",
                ]
            ),
            use_case=rng.choice(
                [
                    "event-driven architecture",
                    "real-time analytics",
                    "distributed transactions",
                ]
            ),
            genre=rng.choice(_CREATIVE_GENRES),
            theme=rng.choice(["identity", "power", "memory", "isolation", "belonging"]),
            subject=rng.choice(
                ["systems design", "machine learning", "compiler design"]
            ),
            audience=rng.choice(
                ["college freshmen", "experienced developers", "non-technical managers"]
            ),
            duration=rng.choice(["8 weeks", "a semester", "a weekend bootcamp"]),
            event=rng.choice(
                ["AI regulation", "climate treaties", "space colonization"]
            ),
            regions=rng.choice(["East Asia", "Europe", "the Americas", "Africa"]),
        )


def split_data(
    data: list[dict], train_ratio: float = 0.8, seed: int = 42
) -> tuple[list[dict], list[dict]]:
    """Split data into train and test sets.

    Uses a separate random seed from generation to ensure the split
    is independent of the data generation order.
    """
    rng = random.Random(seed + 1)  # Different seed from generation
    shuffled = list(data)
    rng.shuffle(shuffled)
    split_idx = int(len(shuffled) * train_ratio)
    return shuffled[:split_idx], shuffled[split_idx:]


def save_jsonl(data: list[dict], path: str | Path) -> None:
    """Save data as JSONL file."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        for entry in data:
            f.write(json.dumps(entry) + "\n")


def load_jsonl(path: str | Path) -> list[dict]:
    """Load data from JSONL file."""
    data = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                data.append(json.loads(line))
    return data
