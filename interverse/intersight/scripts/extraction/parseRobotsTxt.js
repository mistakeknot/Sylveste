(() => {
  try {
    const targetPath = '__TARGET_PATH__'; // Replaced by SKILL.md before evaluation
    const text = document.body?.innerText || '';
    if (!text.trim()) return JSON.stringify({ allowed: true, reason: 'no robots.txt found' });

    const lines = text.split('\n').map(l => l.trim());
    let inRelevantBlock = false;
    const allowedPaths = [];
    const disallowedPaths = [];

    for (const line of lines) {
      if (line.startsWith('#') || !line) continue;

      const lower = line.toLowerCase();
      if (lower.startsWith('user-agent:')) {
        const agent = lower.replace('user-agent:', '').trim();
        inRelevantBlock = agent === '*' || agent.includes('mozilla') || agent.includes('chrome');
      } else if (inRelevantBlock) {
        if (lower.startsWith('disallow:')) {
          const path = line.substring(line.indexOf(':') + 1).trim();
          if (path) disallowedPaths.push(path);
        } else if (lower.startsWith('allow:')) {
          const path = line.substring(line.indexOf(':') + 1).trim();
          if (path) allowedPaths.push(path);
        }
      }
    }

    // RFC 9309: most specific path wins (longest match). Allow > Disallow at same length.
    let bestAllow = '';
    let bestDisallow = '';
    for (const p of allowedPaths) {
      if (targetPath.startsWith(p) && p.length > bestAllow.length) bestAllow = p;
    }
    for (const p of disallowedPaths) {
      if (targetPath.startsWith(p) && p.length > bestDisallow.length) bestDisallow = p;
    }

    if (bestDisallow && bestDisallow.length > bestAllow.length) {
      return JSON.stringify({
        allowed: false,
        reason: 'disallowed by robots.txt: Disallow ' + bestDisallow + ' matches ' + targetPath,
        matchedRule: bestDisallow
      });
    }
    if (bestAllow) {
      return JSON.stringify({ allowed: true, reason: 'explicitly allowed: Allow ' + bestAllow });
    }
    if (disallowedPaths.length === 0) {
      return JSON.stringify({ allowed: true, reason: 'no matching disallow rules' });
    }
    return JSON.stringify({ allowed: true, reason: 'no disallow rule matches ' + targetPath });
  } catch (e) {
    // FAIL-CLOSED: parse errors block extraction (mandatory compliance)
    return JSON.stringify({ allowed: false, reason: 'parse error (fail-closed): ' + e.message });
  }
})()
