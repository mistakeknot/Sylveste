(() => {
  try {
    // Count total CSS rules across accessible stylesheets (deployment-stable)
    let ruleCount = 0;
    const sheetHrefs = [];
    for (const sheet of document.styleSheets) {
      try {
        ruleCount += sheet.cssRules?.length || 0;
        if (sheet.href) sheetHrefs.push(sheet.href);
      } catch (_) {
        // Cross-origin — count the sheet but not rules
        if (sheet.href) sheetHrefs.push(sheet.href);
      }
    }

    // Sample custom property names from :root (stable across sessions)
    const rootProps = [];
    const rootStyles = getComputedStyle(document.documentElement);
    for (let i = 0; i < rootStyles.length && rootProps.length < 20; i++) {
      if (rootStyles[i].startsWith('--')) rootProps.push(rootStyles[i]);
    }

    const sig = [
      document.querySelectorAll('*').length,
      document.styleSheets.length,
      ruleCount,
      rootProps.sort().join(','),
      sheetHrefs.sort().join(','),
      getComputedStyle(document.documentElement).getPropertyValue('--version') || ''
    ].join(':');
    return JSON.stringify({ hash: sig, timestamp: new Date().toISOString() });
  } catch (e) {
    return JSON.stringify({ hash: 'error', error: e.message });
  }
})()
