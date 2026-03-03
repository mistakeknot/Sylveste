(() => {
  try {
    const colorMap = {};
    const colorProps = ['color', 'backgroundColor', 'borderColor', 'outlineColor',
                        'borderTopColor', 'borderRightColor', 'borderBottomColor', 'borderLeftColor'];

    const elements = document.querySelectorAll('body *');
    const sampleLimit = Math.min(elements.length, 2000);

    for (let i = 0; i < sampleLimit; i++) {
      const el = elements[i];
      const styles = getComputedStyle(el);
      for (const prop of colorProps) {
        const val = styles[prop];
        if (val && val !== 'rgba(0, 0, 0, 0)' && val !== 'transparent') {
          if (!colorMap[val]) {
            colorMap[val] = { value: val, frequency: 0, contexts: new Set() };
          }
          colorMap[val].frequency++;
          const tag = el.tagName.toLowerCase();
          if (colorMap[val].contexts.size < 5) {
            colorMap[val].contexts.add(tag);
          }
        }
      }
    }

    // Sort by frequency, cap at 100
    const sorted = Object.entries(colorMap)
      .sort((a, b) => b[1].frequency - a[1].frequency)
      .slice(0, 100)
      .map(([key, data]) => ({
        value: data.value,
        frequency: data.frequency,
        contexts: Array.from(data.contexts)
      }));

    return JSON.stringify({ count: sorted.length, colors: sorted });
  } catch (e) {
    return JSON.stringify({ count: 0, colors: [], error: e.message });
  }
})()
