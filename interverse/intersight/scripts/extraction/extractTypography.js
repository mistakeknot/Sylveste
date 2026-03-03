(() => {
  try {
    const typoMap = {};
    const textElements = document.querySelectorAll('body h1, body h2, body h3, body h4, body h5, body h6, body p, body span, body a, body li, body td, body th, body label, body button, body input, body textarea, body div, body section');
    const sampleLimit = Math.min(textElements.length, 1500);

    for (let i = 0; i < sampleLimit; i++) {
      const el = textElements[i];
      if (!el.textContent?.trim()) continue;

      const styles = getComputedStyle(el);
      const key = [
        styles.fontFamily,
        styles.fontSize,
        styles.fontWeight,
        styles.lineHeight,
        styles.letterSpacing
      ].join('|');

      if (!typoMap[key]) {
        typoMap[key] = {
          fontFamily: styles.fontFamily.split(',').map(f => f.trim().replace(/['"]/g, '')),
          fontSize: styles.fontSize,
          fontWeight: parseInt(styles.fontWeight) || 400,
          lineHeight: styles.lineHeight,
          letterSpacing: styles.letterSpacing,
          frequency: 0,
          sampleTags: new Set()
        };
      }
      typoMap[key].frequency++;
      if (typoMap[key].sampleTags.size < 3) {
        typoMap[key].sampleTags.add(el.tagName.toLowerCase());
      }
    }

    const sorted = Object.values(typoMap)
      .sort((a, b) => b.frequency - a.frequency)
      .slice(0, 30)
      .map(t => ({
        fontFamily: t.fontFamily,
        fontSize: t.fontSize,
        fontWeight: t.fontWeight,
        lineHeight: t.lineHeight,
        letterSpacing: t.letterSpacing,
        frequency: t.frequency,
        sampleTags: Array.from(t.sampleTags)
      }));

    return JSON.stringify({ count: sorted.length, typography: sorted });
  } catch (e) {
    return JSON.stringify({ count: 0, typography: [], error: e.message });
  }
})()
