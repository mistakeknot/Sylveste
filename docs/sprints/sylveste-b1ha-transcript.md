# Review this dependency-audit diff only. Context: private Astro static site…

*Started: 2026-04-26 04:28 UTC*

---

## unknown

Review this dependency-audit diff only. Context: private Astro static site generalsystemsventures; goal is to clear Dependabot advisories for defu, vite, astro, postcss with minimal behavior change. Focus on lockfile correctness, semver risk, build/test/deployment safety, and whether any vulnerable versions remain. Do not modify files. Return sections: Critical, Warnings, Suggestions, Looks Good.
diff --git a/package.json b/package.json
index 6e31a02..1a4123b 100644
--- a/package.json
+++ b/package.json
@@ -13,11 +13,11 @@
     "test": "node --test"
   },
   "dependencies": {
-    "@astrojs/mdx": "^5.0.2",
-    "@astrojs/sitemap": "^3.7.1",
-    "@tailwindcss/vite": "^4.2.2",
-    "astro": "^6.0.8",
-    "tailwindcss": "^4.2.2"
+    "@astrojs/mdx": "^5.0.4",
+    "@astrojs/sitemap": "^3.7.2",
+    "@tailwindcss/vite": "^4.2.4",
+    "astro": "^6.1.9",
+    "tailwindcss": "^4.2.4"
   },
   "packageManager": "pnpm@10.33.0"
 }
diff --git a/pnpm-lock.yaml b/pnpm-lock.yaml
index 07d73be..a66905b 100644
--- a/pnpm-lock.yaml
+++ b/pnpm-lock.yaml
@@ -9,34 +9,34 @@ importers:
   .:
     dependencies:
       '@astrojs/mdx':
-        specifier: ^5.0.2
-        version: 5.0.3(astro@6.1.1(@types/node@24.12.0)(@vercel/functions@3.4.3)(jiti@2.6.1)(lightningcss@1.32.0)(rollup@4.60.0))
+        specifier: ^5.0.4
+        version: 5.0.4(astro@6.1.9(@types/node@24.12.2)(@vercel/functions@3.4.3)(jiti@2.6.1)(lightningcss@1.32.0)(rollup@4.60.2))
       '@astrojs/sitemap':
-        specifier: ^3.7.1
+        specifier: ^3.7.2
         version: 3.7.2
       '@tailwindcss/vite':
-        specifier: ^4.2.2
-        version: 4.2.2(vite@7.3.1(@types/node@24.12.0)(jiti@2.6.1)(lightningcss@1.32.0))
+        specifier: ^4.2.4
+        version: 4.2.4(vite@7.3.2(@types/node@24.12.2)(jiti@2.6.1)(lightningcss@1.32.0))
       astro:
-        specifier: ^6.0.8
-        version: 6.1.1(@types/node@24.12.0)(@vercel/functions@3.4.3)(jiti@2.6.1)(lightningcss@1.32.0)(rollup@4.60.0)
+        specifier: ^6.1.9
+        version: 6.1.9(@types/node@24.12.2)(@vercel/functions@3.4.3)(jiti@2.6.1)(lightningcss@1.32.0)(rollup@4.60.2)
       tailwindcss:
-        specifier: ^4.2.2
-        version: 4.2.2
+        specifier: ^4.2.4
+        version: 4.2.4
 
 packages:
 
   '@astrojs/compiler@3.0.1':
     resolution: {integrity: sha512-z97oYbdebO5aoWzuJ/8q5hLK232+17KcLZ7cJ8BCWk6+qNzVxn/gftC0KzMBUTD8WAaBkPpNSQK6PXLnNrZ0CA==}
 
-  '@astrojs/internal-helpers@0.8.0':
-    resolution: {integrity: sha512-J56GrhEiV+4dmrGLPNOl2pZjpHXAndWVyiVDYGDuw6MWKpBSEMLdFxHzeM/6sqaknw9M+HFfHZAcvi3OfT3D/w==}
+  '@astrojs/internal-helpers@0.9.0':
+    resolution: {integrity: sha512-GdYkzR26re8izmyYlBqf4z2s7zNngmWLFuxw0UKiPNqHraZGS6GKWIwSHgS22RDlu2ePFJ8bzmpBcUszut/SDg==}
 
-  '@astrojs/markdown-remark@7.1.0':
-    resolution: {integrity: sha512-P+HnCsu2js3BoTc8kFmu+E9gOcFeMdPris75g+Zl4sY8+bBRbSQV6xzcBDbZ27eE7yBGEGQoqjpChx+KJYIPYQ==}
+  '@astrojs/markdown-remark@7.1.1':
+    resolution: {integrity: sha512-C6e9BnLGlbdv6bV8MYGeHpHxsUHrCrB4OuRLqi5LI7oiBVcBcqfUN06zpwFQdHgV48QCCrMmLpyqBr7VqC+swA==}
 
-  '@astrojs/mdx@5.0.3':
-    resolution: {integrity: sha512-zv/OlM5sZZvyjHqJjR3FjJvoCgbxdqj3t4jO/gSEUNcck3BjdtMgNQw8UgPfAGe4yySdG4vjZ3OC5wUxhu7ckg==}
+  '@astrojs/mdx@5.0.4':
+    resolution: {integrity: sha512-tSbuuYueNODiFAFaME7pjHY5lOLoxBYJi1cKd6scw9+a4ZO7C7UGdafEoVAQvOV2eO8a6RaHSAJYGVPL1w8BPA==}
     engines: {node: '>=22.12.0'}
     peerDependencies:
       astro: ^6.0.0
@@ -48,8 +48,8 @@ packages:
   '@astrojs/sitemap@3.7.2':
     resolution: {integrity: sha512-PqkzkcZTb5ICiyIR8VoKbIAP/laNRXi5tw616N1Ckk+40oNB8Can1AzVV56lrbC5GKSZFCyJYUVYqVivMisvpA==}
 
-  '@astrojs/telemetry@3.3.0':
-    resolution: {integrity: sha512-UFBgfeldP06qu6khs/yY+q1cDAaArM2/7AEIqQ9Cuvf7B1hNLq0xDrZkct+QoIGyjq56y8IaE2I3CTvG99mlhQ==}
+  '@astrojs/telemetry@3.3.1':
+    resolution: {integrity: sha512-7fcIxXS9J4ls5tr8b3ww9rbAIz2+HrhNJYZdkAhhB4za/I5IZ/60g+Bs8q7zwG0tOIZfNB4JWhVJ1Qkl/OrNCw==}
     engines: {node: 18.20.8 || ^20.3.0 || >=22.0.0}
 
   '@babel/helper-string-parser@7.27.1':
@@ -73,167 +73,167 @@ packages:
     resolution: {integrity: sha512-VERIM64vtTP1C4mxQ5thVT9fK0apjPFobqybMtA1UdUujWka24ERHbRHFGmpbbhp73MhV+KSsHQH9C6uOTdEQA==}
     engines: {node: '>=18'}
 
-  '@clack/core@1.1.0':
-    resolution: {integrity: sha512-SVcm4Dqm2ukn64/8Gub2wnlA5nS2iWJyCkdNHcvNHPIeBTGojpdJ+9cZKwLfmqy7irD4N5qLteSilJlE0WLAtA==}
+  '@clack/core@1.2.0':
+    resolution: {integrity: sha512-qfxof/3T3t9DPU/Rj3OmcFyZInceqj/NVtO9rwIuJqCUgh32gwPjpFQQp/ben07qKlhpwq7GzfWpST4qdJ5Drg==}
 
-  '@clack/prompts@1.1.0':
-    resolution: {integrity: sha512-pkqbPGtohJAvm4Dphs2M8xE29ggupihHdy1x84HNojZuMtFsHiUlRvqD24tM2+XmI+61LlfNceM3Wr7U5QES5g==}
+  '@clack/prompts@1.2.0':
+    resolution: {integrity: sha512-4jmztR9fMqPMjz6H/UZXj0zEmE43ha1euENwkckKKel4XpSfokExPo5AiVStdHSAlHekz4d0CA/r45Ok1E4D3w==}
 
-  '@emnapi/runtime@1.9.1':
-    resolution: {integrity: sha512-VYi5+ZVLhpgK4hQ0TAjiQiZ6ol0oe4mBx7mVv7IflsiEp0OWoVsp/+f9Vc1hOhE0TtkORVrI1GvzyreqpgWtkA==}
+  '@emnapi/runtime@1.10.0':
+    resolution: {integrity: sha512-ewvYlk86xUoGI0zQRNq/mC+16R1QeDlKQy21Ki3oSYXNgLb45GV1P6A0M+/s6nyCuNDqe5VpaY84BzXGwVbwFA==}
 
-  '@esbuild/aix-ppc64@0.27.4':
-    resolution: {integrity: sha512-cQPwL2mp2nSmHHJlCyoXgHGhbEPMrEEU5xhkcy3Hs/O7nGZqEpZ2sUtLaL9MORLtDfRvVl2/3PAuEkYZH0Ty8Q==}
+  '@esbuild/aix-ppc64@0.27.7':
+    resolution: {integrity: sha512-EKX3Qwmhz1eMdEJokhALr0YiD0lhQNwDqkPYyPhiSwKrh7/4KRjQc04sZ8db+5DVVnZ1LmbNDI1uAMPEUBnQPg==}
     engines: {node: '>=18'}
     cpu: [ppc64]
     os: [aix]
 
-  '@esbuild/android-arm64@0.27.4':
-    resolution: {integrity: sha512-gdLscB7v75wRfu7QSm/zg6Rx29VLdy9eTr2t44sfTW7CxwAtQghZ4ZnqHk3/ogz7xao0QAgrkradbBzcqFPasw==}
+  '@esbuild/android-arm64@0.27.7':
+    resolution: {integrity: sha512-62dPZHpIXzvChfvfLJow3q5dDtiNMkwiRzPylSCfriLvZeq0a1bWChrGx/BbUbPwOrsWKMn8idSllklzBy+dgQ==}
     engines: {node: '>=18'}
     cpu: [arm64]
     os: [android]
 
-  '@esbuild/android-arm@0.27.4':
-    resolution: {integrity: sha512-X9bUgvxiC8CHAGKYufLIHGXPJWnr0OCdR0anD2e21vdvgCI8lIfqFbnoeOz7lBjdrAGUhqLZLcQo6MLhTO2DKQ==}
+  '@esbuild/android-arm@0.27.7':
+    resolution: {integrity: sha512-jbPXvB4Yj2yBV7HUfE2KHe4GJX51QplCN1pGbYjvsyCZbQmies29EoJbkEc+vYuU5o45AfQn37vZlyXy4YJ8RQ==}
     engines: {node: '>=18'}
     cpu: [arm]
     os: [android]
 
-  '@esbuild/android-x64@0.27.4':
-    resolution: {integrity: sha512-PzPFnBNVF292sfpfhiyiXCGSn9HZg5BcAz+ivBuSsl6Rk4ga1oEXAamhOXRFyMcjwr2DVtm40G65N3GLeH1Lvw==}
+  '@esbuild/android-x64@0.27.7':
+    resolution: {integrity: sha512-x5VpMODneVDb70PYV2VQOmIUUiBtY3D3mPBG8NxVk5CogneYhkR7MmM3yR/uMdITLrC1ml/NV1rj4bMJuy9MCg==}
     engines: {node: '>=18'}
     cpu: [x64]
     os: [android]
 
-  '@esbuild/darwin-arm64@0.27.4':
-    resolution: {integrity: sha512-b7xaGIwdJlht8ZFCvMkpDN6uiSmnxxK56N2GDTMYPr2/gzvfdQN8rTfBsvVKmIVY/X7EM+/hJKEIbbHs9oA4tQ==}
+  '@esbuild/darwin-arm64@0.27.7':
+    resolution: {integrity: sha512-5lckdqeuBPlKUwvoCXIgI2D9/ABmPq3Rdp7IfL70393YgaASt7tbju3Ac+ePVi3KDH6N2RqePfHnXkaDtY9fkw==}
     engines: {node: '>=18'}
     cpu: [arm64]
     os: [darwin]
 
-  '@esbuild/darwin-x64@0.27.4':
-    resolution: {integrity: sha512-sR+OiKLwd15nmCdqpXMnuJ9W2kpy0KigzqScqHI3Hqwr7IXxBp3Yva+yJwoqh7rE8V77tdoheRYataNKL4QrPw==}
+  '@esbuild/darwin-x64@0.27.7':
+    resolution: {integrity: sha512-rYnXrKcXuT7Z+WL5K980jVFdvVKhCHhUwid+dDYQpH+qu+TefcomiMAJpIiC2EM3Rjtq0sO3StMV/+3w3MyyqQ==}
     engines: {node: '>=18'}
     cpu: [x64]
     os: [darwin]
 
-  '@esbuild/freebsd-arm64@0.27.4':
-    resolution: {integrity: sha512-jnfpKe+p79tCnm4GVav68A7tUFeKQwQyLgESwEAUzyxk/TJr4QdGog9sqWNcUbr/bZt/O/HXouspuQDd9JxFSw==}
+  '@esbuild/freebsd-arm64@0.27.7':
+    resolution: {integrity: sha512-B48PqeCsEgOtzME2GbNM2roU29AMTuOIN91dsMO30t+Ydis3z/3Ngoj5hhnsOSSwNzS+6JppqWsuhTp6E82l2w==}
     engines: {node: '>=18'}
     cpu: [arm64]
     os: [freebsd]
 
-  '@esbuild/freebsd-x64@0.27.4':
-    resolution: {integrity: sha512-2kb4ceA/CpfUrIcTUl1wrP/9ad9Atrp5J94Lq69w7UwOMolPIGrfLSvAKJp0RTvkPPyn6CIWrNy13kyLikZRZQ==}
+  '@esbuild/freebsd-x64@0.27.7':
+    resolution: {integrity: sha512-jOBDK5XEjA4m5IJK3bpAQF9/Lelu/Z9ZcdhTRLf4cajlB+8VEhFFRjWgfy3M1O4rO2GQ/b2dLwCUGpiF/eATNQ==}
     engines: {node: '>=18'}
     cpu: [x64]
     os: [freebsd]
 
-  '@esbuild/linux-arm64@0.27.4':
-    resolution: {integrity: sha512-7nQOttdzVGth1iz57kxg9uCz57dxQLHWxopL6mYuYthohPKEK0vU0C3O21CcBK6KDlkYVcnDXY099HcCDXd9dA==}
+  '@esbuild/linux-arm64@0.27.7':
+    resolution: {integrity: sha512-RZPHBoxXuNnPQO9rvjh5jdkRmVizktkT7TCDkDmQ0W2SwHInKCAV95GRuvdSvA7w4VMwfCjUiPwDi0ZO6Nfe9A==}
     engines: {node: '>=18'}
     cpu: [arm64]
     os: [linux]
 
-  '@esbuild/linux-arm@0.27.4':
-    resolution: {integrity: sha512-aBYgcIxX/wd5n2ys0yESGeYMGF+pv6g0DhZr3G1ZG4jMfruU9Tl1i2Z+Wnj9/KjGz1lTLCcorqE2viePZqj4Eg==}
+  '@esbuild/linux-arm@0.27.7':
+    resolution: {integrity: sha512-RkT/YXYBTSULo3+af8Ib0ykH8u2MBh57o7q/DAs3lTJlyVQkgQvlrPTnjIzzRPQyavxtPtfg0EopvDyIt0j1rA==}
     engines: {node: '>=18'}
     cpu: [arm]
     os: [linux]
 
-  '@esbuild/linux-ia32@0.27.4':
-    resolution: {integrity: sha512-oPtixtAIzgvzYcKBQM/qZ3R+9TEUd1aNJQu0HhGyqtx6oS7qTpvjheIWBbes4+qu1bNlo2V4cbkISr8q6gRBFA==}
+  '@esbuild/linux-ia32@0.27.7':
+    resolution: {integrity: sha512-GA48aKNkyQDbd3KtkplYWT102C5sn/EZTY4XROkxONgruHPU72l+gW+FfF8tf2cFjeHaRbWpOYa/uRBz/Xq1Pg==}
     engines: {node: '>=18'}
     cpu: [ia32]
     os: [linux]
 
-  '@esbuild/linux-loong64@0.27.4':
-    resolution: {integrity: sha512-8mL/vh8qeCoRcFH2nM8wm5uJP+ZcVYGGayMavi8GmRJjuI3g1v6Z7Ni0JJKAJW+m0EtUuARb6Lmp4hMjzCBWzA==}
+  '@esbuild/linux-loong64@0.27.7':
+    resolution: {integrity: sha512-a4POruNM2oWsD4WKvBSEKGIiWQF8fZOAsycHOt6JBpZ+JN2n2JH9WAv56SOyu9X5IqAjqSIPTaJkqN8F7XOQ5Q==}
     engines: {node: '>=18'}
     cpu: [loong64]
     os: [linux]
 
-  '@esbuild/linux-mips64el@0.27.4':
-    resolution: {integrity: sha512-1RdrWFFiiLIW7LQq9Q2NES+HiD4NyT8Itj9AUeCl0IVCA459WnPhREKgwrpaIfTOe+/2rdntisegiPWn/r/aAw==}
+  '@esbuild/linux-mips64el@0.27.7':
+    resolution: {integrity: sha512-KabT5I6StirGfIz0FMgl1I+R1H73Gp0ofL9A3nG3i/cYFJzKHhouBV5VWK1CSgKvVaG4q1RNpCTR2LuTVB3fIw==}
     engines: {node: '>=18'}
     cpu: [mips64el]
     os: [linux]
 
-  '@esbuild/linux-ppc64@0.27.4':
-    resolution: {integrity: sha512-tLCwNG47l3sd9lpfyx9LAGEGItCUeRCWeAx6x2Jmbav65nAwoPXfewtAdtbtit/pJFLUWOhpv0FpS6GQAmPrHA==}
+  '@esbuild/linux-ppc64@0.27.7':
+    resolution: {integrity: sha512-gRsL4x6wsGHGRqhtI+ifpN/vpOFTQtnbsupUF5R5YTAg+y/lKelYR1hXbnBdzDjGbMYjVJLJTd2OFmMewAgwlQ==}
     engines: {node: '>=18'}
     cpu: [ppc64]
     os: [linux]
 
-  '@esbuild/linux-riscv64@0.27.4':
-    resolution: {integrity: sha512-BnASypppbUWyqjd1KIpU4AUBiIhVr6YlHx/cnPgqEkNoVOhHg+YiSVxM1RLfiy4t9cAulbRGTNCKOcqHrEQLIw==}
+  '@esbuild/linux-riscv64@0.27.7':
+    resolution: {integrity: sha512-hL25LbxO1QOngGzu2U5xeXtxXcW+/GvMN3ejANqXkxZ/opySAZMrc+9LY/WyjAan41unrR3YrmtTsUpwT66InQ==}
     engines: {node: '>=18'}
     cpu: [riscv64]
     os: [linux]
 
-  '@esbuild/linux-s390x@0.27.4':
-    resolution: {integrity: sha512-+eUqgb/Z7vxVLezG8bVB9SfBie89gMueS+I0xYh2tJdw3vqA/0ImZJ2ROeWwVJN59ihBeZ7Tu92dF/5dy5FttA==}
+  '@esbuild/linux-s390x@0.27.7':
+    resolution: {integrity: sha512-2k8go8Ycu1Kb46vEelhu1vqEP+UeRVj2zY1pSuPdgvbd5ykAw82Lrro28vXUrRmzEsUV0NzCf54yARIK8r0fdw==}
     engines: {node: '>=18'}
     cpu: [s390x]
     os: [linux]
 
-  '@esbuild/linux-x64@0.27.4':
-    resolution: {integrity: sha512-S5qOXrKV8BQEzJPVxAwnryi2+Iq5pB40gTEIT69BQONqR7JH1EPIcQ/Uiv9mCnn05jff9umq/5nqzxlqTOg9NA==}
+  '@esbuild/linux-x64@0.27.7':
+    resolution: {integrity: sha512-hzznmADPt+OmsYzw1EE33ccA+HPdIqiCRq7cQeL1Jlq2gb1+OyWBkMCrYGBJ+sxVzve2ZJEVeePbLM2iEIZSxA==}
     engines: {node: '>=18'}
     cpu: [x64]
     os: [linux]
 
-  '@esbuild/netbsd-arm64@0.27.4':
-    resolution: {integrity: sha512-xHT8X4sb0GS8qTqiwzHqpY00C95DPAq7nAwX35Ie/s+LO9830hrMd3oX0ZMKLvy7vsonee73x0lmcdOVXFzd6Q==}
+  '@esbuild/netbsd-arm64@0.27.7':
+    resolution: {integrity: sha512-b6pqtrQdigZBwZxAn1UpazEisvwaIDvdbMbmrly7cDTMFnw/+3lVxxCTGOrkPVnsYIosJJXAsILG9XcQS+Yu6w==}
     engines: {node: '>=18'}
     cpu: [arm64]
     os: [netbsd]
 
-  '@esbuild/netbsd-x64@0.27.4':
-    resolution: {integrity: sha512-RugOvOdXfdyi5Tyv40kgQnI0byv66BFgAqjdgtAKqHoZTbTF2QqfQrFwa7cHEORJf6X2ht+l9ABLMP0dnKYsgg==}
+  '@esbuild/netbsd-x64@0.27.7':
+    resolution: {integrity: sha512-OfatkLojr6U+WN5EDYuoQhtM+1xco+/6FSzJJnuWiUw5eVcicbyK3dq5EeV/QHT1uy6GoDhGbFpprUiHUYggrw==}
     engines: {node: '>=18'}
     cpu: [x64]
     os: [netbsd]
 
-  '@esbuild/openbsd-arm64@0.27.4':
-    resolution: {integrity: sha512-2MyL3IAaTX+1/qP0O1SwskwcwCoOI4kV2IBX1xYnDDqthmq5ArrW94qSIKCAuRraMgPOmG0RDTA74mzYNQA9ow==}
+  '@esbuild/openbsd-arm64@0.27.7':
+    resolution: {integrity: sha512-AFuojMQTxAz75Fo8idVcqoQWEHIXFRbOc1TrVcFSgCZtQfSdc1RXgB3tjOn/krRHENUB4j00bfGjyl2mJrU37A==}
     engines: {node: '>=18'}
     cpu: [arm64]
     os: [openbsd]
 
-  '@esbuild/openbsd-x64@0.27.4':
-    resolution: {integrity: sha512-u8fg/jQ5aQDfsnIV6+KwLOf1CmJnfu1ShpwqdwC0uA7ZPwFws55Ngc12vBdeUdnuWoQYx/SOQLGDcdlfXhYmXQ==}
+  '@esbuild/openbsd-x64@0.27.7':
+    resolution: {integrity: sha512-+A1NJmfM8WNDv5CLVQYJ5PshuRm/4cI6WMZRg1by1GwPIQPCTs1GLEUHwiiQGT5zDdyLiRM/l1G0Pv54gvtKIg==}
     engines: {node: '>=18'}
     cpu: [x64]
     os: [openbsd]
 
-  '@esbuild/openharmony-arm64@0.27.4':
-    resolution: {integrity: sha512-JkTZrl6VbyO8lDQO3yv26nNr2RM2yZzNrNHEsj9bm6dOwwu9OYN28CjzZkH57bh4w0I2F7IodpQvUAEd1mbWXg==}
+  '@esbuild/openharmony-arm64@0.27.7':
+    resolution: {integrity: sha512-+KrvYb/C8zA9CU/g0sR6w2RBw7IGc5J2BPnc3dYc5VJxHCSF1yNMxTV5LQ7GuKteQXZtspjFbiuW5/dOj7H4Yw==}
     engines: {node: '>=18'}
     cpu: [arm64]
     os: [openharmony]
 
-  '@esbuild/sunos-x64@0.27.4':
-    resolution: {integrity: sha512-/gOzgaewZJfeJTlsWhvUEmUG4tWEY2Spp5M20INYRg2ZKl9QPO3QEEgPeRtLjEWSW8FilRNacPOg8R1uaYkA6g==}
+  '@esbuild/sunos-x64@0.27.7':
+    resolution: {integrity: sha512-ikktIhFBzQNt/QDyOL580ti9+5mL/YZeUPKU2ivGtGjdTYoqz6jObj6nOMfhASpS4GU4Q/Clh1QtxWAvcYKamA==}
     engines: {node: '>=18'}
     cpu: [x64]
     os: [sunos]
 
-  '@esbuild/win32-arm64@0.27.4':
-    resolution: {integrity: sha512-Z9SExBg2y32smoDQdf1HRwHRt6vAHLXcxD2uGgO/v2jK7Y718Ix4ndsbNMU/+1Qiem9OiOdaqitioZwxivhXYg==}
+  '@esbuild/win32-arm64@0.27.7':
+    resolution: {integrity: sha512-7yRhbHvPqSpRUV7Q20VuDwbjW5kIMwTHpptuUzV+AA46kiPze5Z7qgt6CLCK3pWFrHeNfDd1VKgyP4O+ng17CA==}
     engines: {node: '>=18'}
     cpu: [arm64]
     os: [win32]
 
-  '@esbuild/win32-ia32@0.27.4':
-    resolution: {integrity: sha512-DAyGLS0Jz5G5iixEbMHi5KdiApqHBWMGzTtMiJ72ZOLhbu/bzxgAe8Ue8CTS3n3HbIUHQz/L51yMdGMeoxXNJw==}
+  '@esbuild/win32-ia32@0.27.7':
+    resolution: {integrity: sha512-SmwKXe6VHIyZYbBLJrhOoCJRB/Z1tckzmgTLfFYOfpMAx63BJEaL9ExI8x7v0oAO3Zh6D/Oi1gVxEYr5oUCFhw==}
     engines: {node: '>=18'}
     cpu: [ia32]
     os: [win32]
 
-  '@esbuild/win32-x64@0.27.4':
-    resolution: {integrity: sha512-+knoa0BDoeXgkNvvV1vvbZX4+hizelrkwmGJBdT17t8FNPwG2lKemmuMZlmaNQ3ws3DKKCxpb4zRZEIp3UxFCg==}
+  '@esbuild/win32-x64@0.27.7':
+    resolution: {integrity: sha512-56hiAJPhwQ1R4i+21FVF7V8kSD5zZTdHcVuRFMW0hn753vVfQN8xlx4uOPT4xoGH0Z/oVATuR82AiqSTDIpaHg==}
     engines: {node: '>=18'}
     cpu: [x64]
     os: [win32]
@@ -422,141 +422,141 @@ packages:
       rollup:
         optional: true
 
-  '@rollup/rollup-android-arm-eabi@4.60.0':
-    resolution: {integrity: sha512-WOhNW9K8bR3kf4zLxbfg6Pxu2ybOUbB2AjMDHSQx86LIF4rH4Ft7vmMwNt0loO0eonglSNy4cpD3MKXXKQu0/A==}
+  '@rollup/rollup-android-arm-eabi@4.60.2':
+    resolution: {integrity: sha512-dnlp69efPPg6Uaw2dVqzWRfAWRnYVb1XJ8CyyhIbZeaq4CA5/mLeZ1IEt9QqQxmbdvagjLIm2ZL8BxXv5lH4Yw==}
     cpu: [arm]
     os: [android]
 
-  '@rollup/rollup-android-arm64@4.60.0':
-    resolution: {integrity: sha512-u6JHLll5QKRvjciE78bQXDmqRqNs5M/3GVqZeMwvmjaNODJih/WIrJlFVEihvV0MiYFmd+ZyPr9wxOVbPAG2Iw==}
+  '@rollup/rollup-android-arm64@4.60.2':
+    resolution: {integrity: sha512-OqZTwDRDchGRHHm/hwLOL7uVPB9aUvI0am/eQuWMNyFHf5PSEQmyEeYYheA0EPPKUO/l0uigCp+iaTjoLjVoHg==}
     cpu: [arm64]
     os: [android]
 
-  '@rollup/rollup-darwin-arm64@4.60.0':
-    resolution: {integrity: sha512-qEF7CsKKzSRc20Ciu2Zw1wRrBz4g56F7r/vRwY430UPp/nt1x21Q/fpJ9N5l47WWvJlkNCPJz3QRVw008fi7yA==}
+  '@rollup/rollup-darwin-arm64@4.60.2':
+    resolution: {integrity: sha512-UwRE7CGpvSVEQS8gUMBe1uADWjNnVgP3Iusyda1nSRwNDCsRjnGc7w6El6WLQsXmZTbLZx9cecegumcitNfpmA==}
     cpu: [arm64]
     os: [darwin]
 
-  '@rollup/rollup-darwin-x64@4.60.0':
-    resolution: {integrity: sha512-WADYozJ4QCnXCH4wPB+3FuGmDPoFseVCUrANmA5LWwGmC6FL14BWC7pcq+FstOZv3baGX65tZ378uT6WG8ynTw==}
+  '@rollup/rollup-darwin-x64@4.60.2':
+    resolution: {integrity: sha512-gjEtURKLCC5VXm1I+2i1u9OhxFsKAQJKTVB8WvDAHF+oZlq0GTVFOlTlO1q3AlCTE/DF32c16ESvfgqR7343/g==}
     cpu: [x64]
     os: [darwin]
 
-  '@rollup/rollup-freebsd-arm64@4.60.0':
-    resolution: {integrity: sha512-6b8wGHJlDrGeSE3aH5mGNHBjA0TTkxdoNHik5EkvPHCt351XnigA4pS7Wsj/Eo9Y8RBU6f35cjN9SYmCFBtzxw==}
+  '@rollup/rollup-freebsd-arm64@4.60.2':
+    resolution: {integrity: sha512-Bcl6CYDeAgE70cqZaMojOi/eK63h5Me97ZqAQoh77VPjMysA/4ORQBRGo3rRy45x4MzVlU9uZxs8Uwy7ZaKnBw==}
     cpu: [arm64]
     os: [freebsd]
 
-  '@rollup/rollup-freebsd-x64@4.60.0':
-    resolution: {integrity: sha512-h25Ga0t4jaylMB8M/JKAyrvvfxGRjnPQIR8lnCayyzEjEOx2EJIlIiMbhpWxDRKGKF8jbNH01NnN663dH638mA==}
+  '@rollup/rollup-freebsd-x64@4.60.2':
+    resolution: {integrity: sha512-LU+TPda3mAE2QB0/Hp5VyeKJivpC6+tlOXd1VMoXV/YFMvk/MNk5iXeBfB4MQGRWyOYVJ01625vjkr0Az98OJQ==}
     cpu: [x64]
     os: [freebsd]
 
-  '@rollup/rollup-linux-arm-gnueabihf@4.60.0':
-    resolution: {integrity: sha512-RzeBwv0B3qtVBWtcuABtSuCzToo2IEAIQrcyB/b2zMvBWVbjo8bZDjACUpnaafaxhTw2W+imQbP2BD1usasK4g==}
+  '@rollup/rollup-linux-arm-gnueabihf@4.60.2':
+    resolution: {integrity: sha512-2QxQrM+KQ7DAW4o22j+XZ6RKdxjLD7BOWTP0Bv0tmjdyhXSsr2Ul1oJDQqh9Zf5qOwTuTc7Ek83mOFaKnodPjg==}
     cpu: [arm]
     os: [linux]
     libc: [glibc]
 
-  '@rollup/rollup-linux-arm-musleabihf@4.60.0':
-    resolution: {integrity: sha512-Sf7zusNI2CIU1HLzuu9Tc5YGAHEZs5Lu7N1ssJG4Tkw6e0MEsN7NdjUDDfGNHy2IU+ENyWT+L2obgWiguWibWQ==}
+  '@rollup/rollup-linux-arm-musleabihf@4.60.2':
+    resolution: {integrity: sha512-TbziEu2DVsTEOPif2mKWkMeDMLoYjx95oESa9fkQQK7r/Orta0gnkcDpzwufEcAO2BLBsD7mZkXGFqEdMRRwfw==}
     cpu: [arm]
     os: [linux]
     libc: [musl]
 
-  '@rollup/rollup-linux-arm64-gnu@4.60.0':
-    resolution: {integrity: sha512-DX2x7CMcrJzsE91q7/O02IJQ5/aLkVtYFryqCjduJhUfGKG6yJV8hxaw8pZa93lLEpPTP/ohdN4wFz7yp/ry9A==}
+  '@rollup/rollup-linux-arm64-gnu@4.60.2':
+    resolution: {integrity: sha512-bO/rVDiDUuM2YfuCUwZ1t1cP+/yqjqz+Xf2VtkdppefuOFS2OSeAfgafaHNkFn0t02hEyXngZkxtGqXcXwO8Rg==}
     cpu: [arm64]
     os: [linux]
     libc: [glibc]
 
-  '@rollup/rollup-linux-arm64-musl@4.60.0':
-    resolution: {integrity: sha512-09EL+yFVbJZlhcQfShpswwRZ0Rg+z/CsSELFCnPt3iK+iqwGsI4zht3secj5vLEs957QvFFXnzAT0FFPIxSrkQ==}
+  '@rollup/rollup-linux-arm64-musl@4.60.2':
+    resolution: {integrity: sha512-hr26p7e93Rl0Za+JwW7EAnwAvKkehh12BU1Llm9Ykiibg4uIr2rbpxG9WCf56GuvidlTG9KiiQT/TXT1yAWxTA==}
     cpu: [arm64]
     os: [linux]
     libc: [musl]
 
-  '@rollup/rollup-linux-loong64-gnu@4.60.0':
-    resolution: {integrity: sha512-i9IcCMPr3EXm8EQg5jnja0Zyc1iFxJjZWlb4wr7U2Wx/GrddOuEafxRdMPRYVaXjgbhvqalp6np07hN1w9kAKw==}
+  '@rollup/rollup-linux-loong64-gnu@4.60.2':
+    resolution: {integrity: sha512-pOjB/uSIyDt+ow3k/RcLvUAOGpysT2phDn7TTUB3n75SlIgZzM6NKAqlErPhoFU+npgY3/n+2HYIQVbF70P9/A==}
     cpu: [loong64]
     os: [linux]
     libc: [glibc]
 
-  '@rollup/rollup-linux-loong64-musl@4.60.0':
-    resolution: {integrity: sha512-DGzdJK9kyJ+B78MCkWeGnpXJ91tK/iKA6HwHxF4TAlPIY7GXEvMe8hBFRgdrR9Ly4qebR/7gfUs9y2IoaVEyog==}
+  '@rollup/rollup-linux-loong64-musl@4.60.2':
+    resolution: {integrity: sha512-2/w+q8jszv9Ww1c+6uJT3OwqhdmGP2/4T17cu8WuwyUuuaCDDJ2ojdyYwZzCxx0GcsZBhzi3HmH+J5pZNXnd+Q==}
     cpu: [loong64]
     os: [linux]
     libc: [musl]
 
-  '@rollup/rollup-linux-ppc64-gnu@4.60.0':
-    resolution: {integrity: sha512-RwpnLsqC8qbS8z1H1AxBA1H6qknR4YpPR9w2XX0vo2Sz10miu57PkNcnHVaZkbqyw/kUWfKMI73jhmfi9BRMUQ==}
+  '@rollup/rollup-linux-ppc64-gnu@4.60.2':
+    resolution: {integrity: sha512-11+aL5vKheYgczxtPVVRhdptAM2H7fcDR5Gw4/bTcteuZBlH4oP9f5s9zYO9aGZvoGeBpqXI/9TZZihZ609wKw==}
     cpu: [ppc64]
     os: [linux]
     libc: [glibc]
 
-  '@rollup/rollup-linux-ppc64-musl@4.60.0':
-    resolution: {integrity: sha512-Z8pPf54Ly3aqtdWC3G4rFigZgNvd+qJlOE52fmko3KST9SoGfAdSRCwyoyG05q1HrrAblLbk1/PSIV+80/pxLg==}
+  '@rollup/rollup-linux-ppc64-musl@4.60.2':
+    resolution: {integrity: sha512-i16fokAGK46IVZuV8LIIwMdtqhin9hfYkCh8pf8iC3QU3LpwL+1FSFGej+O7l3E/AoknL6Dclh2oTdnRMpTzFQ==}
     cpu: [ppc64]
     os: [linux]
     libc: [musl]
 
-  '@rollup/rollup-linux-riscv64-gnu@4.60.0':
-    resolution: {integrity: sha512-3a3qQustp3COCGvnP4SvrMHnPQ9d1vzCakQVRTliaz8cIp/wULGjiGpbcqrkv0WrHTEp8bQD/B3HBjzujVWLOA==}
+  '@rollup/rollup-linux-riscv64-gnu@4.60.2':
+    resolution: {integrity: sha512-49FkKS6RGQoriDSK/6E2GkAsAuU5kETFCh7pG4yD/ylj9rKhTmO3elsnmBvRD4PgJPds5W2PkhC82aVwmUcJ7A==}
     cpu: [riscv64]
     os: [linux]
     libc: [glibc]
 
-  '@rollup/rollup-linux-riscv64-musl@4.60.0':
-    resolution: {integrity: sha512-pjZDsVH/1VsghMJ2/kAaxt6dL0psT6ZexQVrijczOf+PeP2BUqTHYejk3l6TlPRydggINOeNRhvpLa0AYpCWSQ==}
+  '@rollup/rollup-linux-riscv64-musl@4.60.2':
+    resolution: {integrity: sha512-mjYNkHPfGpUR00DuM1ZZIgs64Hpf4bWcz9Z41+4Q+pgDx73UwWdAYyf6EG/lRFldmdHHzgrYyge5akFUW0D3mQ==}
     cpu: [riscv64]
     os: [linux]
     libc: [musl]
 
-  '@rollup/rollup-linux-s390x-gnu@4.60.0':
-    resolution: {integrity: sha512-3ObQs0BhvPgiUVZrN7gqCSvmFuMWvWvsjG5ayJ3Lraqv+2KhOsp+pUbigqbeWqueGIsnn+09HBw27rJ+gYK4VQ==}
+  '@rollup/rollup-linux-s390x-gnu@4.60.2':
+    resolution: {integrity: sha512-ALyvJz965BQk8E9Al/JDKKDLH2kfKFLTGMlgkAbbYtZuJt9LU8DW3ZoDMCtQpXAltZxwBHevXz5u+gf0yA0YoA==}
     cpu: [s390x]
     os: [linux]
     libc: [glibc]
 
-  '@rollup/rollup-linux-x64-gnu@4.60.0':
-    resolution: {integrity: sha512-EtylprDtQPdS5rXvAayrNDYoJhIz1/vzN2fEubo3yLE7tfAw+948dO0g4M0vkTVFhKojnF+n6C8bDNe+gDRdTg==}
+  '@rollup/rollup-linux-x64-gnu@4.60.2':
+    resolution: {integrity: sha512-UQjrkIdWrKI626Du8lCQ6MJp/6V1LAo2bOK9OTu4mSn8GGXIkPXk/Vsp4bLHCd9Z9Iz2OTEaokUE90VweJgIYQ==}
     cpu: [x64]
     os: [linux]
     libc: [glibc]
 
-  '@rollup/rollup-linux-x64-musl@4.60.0':
-    resolution: {integrity: sha512-k09oiRCi/bHU9UVFqD17r3eJR9bn03TyKraCrlz5ULFJGdJGi7VOmm9jl44vOJvRJ6P7WuBi/s2A97LxxHGIdw==}
+  '@rollup/rollup-linux-x64-musl@4.60.2':
+    resolution: {integrity: sha512-bTsRGj6VlSdn/XD4CGyzMnzaBs9bsRxy79eTqTCBsA8TMIEky7qg48aPkvJvFe1HyzQ5oMZdg7AnVlWQSKLTnw==}
     cpu: [x64]
     os: [linux]
     libc: [musl]
 
-  '@rollup/rollup-openbsd-x64@4.60.0':
-    resolution: {integrity: sha512-1o/0/pIhozoSaDJoDcec+IVLbnRtQmHwPV730+AOD29lHEEo4F5BEUB24H0OBdhbBBDwIOSuf7vgg0Ywxdfiiw==}
+  '@rollup/rollup-openbsd-x64@4.60.2':
+    resolution: {integrity: sha512-6d4Z3534xitaA1FcMWP7mQPq5zGwBmGbhphh2DwaA1aNIXUu3KTOfwrWpbwI4/Gr0uANo7NTtaykFyO2hPuFLg==}
     cpu: [x64]
     os: [openbsd]
 
-  '@rollup/rollup-openharmony-arm64@4.60.0':
-    resolution: {integrity: sha512-pESDkos/PDzYwtyzB5p/UoNU/8fJo68vcXM9ZW2V0kjYayj1KaaUfi1NmTUTUpMn4UhU4gTuK8gIaFO4UGuMbA==}
+  '@rollup/rollup-openharmony-arm64@4.60.2':
+    resolution: {integrity: sha512-NetAg5iO2uN7eB8zE5qrZ3CSil+7IJt4WDFLcC75Ymywq1VZVD6qJ6EvNLjZ3rEm6gB7XW5JdT60c6MN35Z85Q==}
     cpu: [arm64]
     os: [openharmony]
 
-  '@rollup/rollup-win32-arm64-msvc@4.60.0':
-    resolution: {integrity: sha512-hj1wFStD7B1YBeYmvY+lWXZ7ey73YGPcViMShYikqKT1GtstIKQAtfUI6yrzPjAy/O7pO0VLXGmUVWXQMaYgTQ==}
+  '@rollup/rollup-win32-arm64-msvc@4.60.2':
+    resolution: {integrity: sha512-NCYhOotpgWZ5kdxCZsv6Iudx0wX8980Q/oW4pNFNihpBKsDbEA1zpkfxJGC0yugsUuyDZ7gL37dbzwhR0VI7pQ==}
     cpu: [arm64]
     os: [win32]
 
-  '@rollup/rollup-win32-ia32-msvc@4.60.0':
-    resolution: {integrity: sha512-SyaIPFoxmUPlNDq5EHkTbiKzmSEmq/gOYFI/3HHJ8iS/v1mbugVa7dXUzcJGQfoytp9DJFLhHH4U3/eTy2Bq4w==}
+  '@rollup/rollup-win32-ia32-msvc@4.60.2':
+    resolution: {integrity: sha512-RXsaOqXxfoUBQoOgvmmijVxJnW2IGB0eoMO7F8FAjaj0UTywUO/luSqimWBJn04WNgUkeNhh7fs7pESXajWmkg==}
     cpu: [ia32]
     os: [win32]
 
-  '@rollup/rollup-win32-x64-gnu@4.60.0':
-    resolution: {integrity: sha512-RdcryEfzZr+lAr5kRm2ucN9aVlCCa2QNq4hXelZxb8GG0NJSazq44Z3PCCc8wISRuCVnGs0lQJVX5Vp6fKA+IA==}
+  '@rollup/rollup-win32-x64-gnu@4.60.2':
+    resolution: {integrity: sha512-qdAzEULD+/hzObedtmV6iBpdL5TIbKVztGiK7O3/KYSf+HIzU257+MX1EXJcyIiDbMAqmbwaufcYPvyRryeZtA==}
     cpu: [x64]
     os: [win32]
 
-  '@rollup/rollup-win32-x64-msvc@4.60.0':
-    resolution: {integrity: sha512-PrsWNQ8BuE00O3Xsx3ALh2Df8fAj9+cvvX9AIA6o4KpATR98c9mud4XtDWVvsEuyia5U4tVSTKygawyJkjm60w==}
+  '@rollup/rollup-win32-x64-msvc@4.60.2':
+    resolution: {integrity: sha512-Nd/SgG27WoA9e+/TdK74KnHz852TLa94ovOYySo/yMPuTmpckK/jIF2jSwS3g7ELSKXK13/cVdmg1Z/DaCWKxA==}
     cpu: [x64]
     os: [win32]
 
@@ -591,69 +591,69 @@ packages:
   '@shikijs/vscode-textmate@10.0.2':
     resolution: {integrity: sha512-83yeghZ2xxin3Nj8z1NMd/NCuca+gsYXswywDy5bHvwlWL8tpTQmzGeUuHd9FC3E/SBEMvzJRwWEOz5gGes9Qg==}
 
-  '@tailwindcss/node@4.2.2':
-    resolution: {integrity: sha512-pXS+wJ2gZpVXqFaUEjojq7jzMpTGf8rU6ipJz5ovJV6PUGmlJ+jvIwGrzdHdQ80Sg+wmQxUFuoW1UAAwHNEdFA==}
+  '@tailwindcss/node@4.2.4':
+    resolution: {integrity: sha512-Ai7+yQPxz3ddrDQzFfBKdHEVBg0w3Zl83jnjuwxnZOsnH9pGn93QHQtpU0p/8rYWxvbFZHneni6p1BSLK4DkGA==}
 
-  '@tailwindcss/oxide-android-arm64@4.2.2':
-    resolution: {integrity: sha512-dXGR1n+P3B6748jZO/SvHZq7qBOqqzQ+yFrXpoOWWALWndF9MoSKAT3Q0fYgAzYzGhxNYOoysRvYlpixRBBoDg==}
+  '@tailwindcss/oxide-android-arm64@4.2.4':
+    resolution: {integrity: sha512-e7MOr1SAn9U8KlZzPi1ZXGZHeC5anY36qjNwmZv9pOJ8E4Q6jmD1vyEHkQFmNOIN7twGPEMXRHmitN4zCMN03g==}
     engines: {node: '>= 20'}
     cpu: [arm64]
     os: [android]
 
-  '@tailwindcss/oxide-darwin-arm64@4.2.2':
-    resolution: {integrity: sha512-iq9Qjr6knfMpZHj55/37ouZeykwbDqF21gPFtfnhCCKGDcPI/21FKC9XdMO/XyBM7qKORx6UIhGgg6jLl7BZlg==}
+  '@tailwindcss/oxide-darwin-arm64@4.2.4':
+    resolution: {integrity: sha512-tSC/Kbqpz/5/o/C2sG7QvOxAKqyd10bq+ypZNf+9Fi2TvbVbv1zNpcEptcsU7DPROaSbVgUXmrzKhurFvo5eDg==}
     engines: {node: '>= 20'}
     cpu: [arm64]
     os: [darwin]
 
-  '@tailwindcss/oxide-darwin-x64@4.2.2':
-    resolution: {integrity: sha512-BlR+2c3nzc8f2G639LpL89YY4bdcIdUmiOOkv2GQv4/4M0vJlpXEa0JXNHhCHU7VWOKWT/CjqHdTP8aUuDJkuw==}
+  '@tailwindcss/oxide-darwin-x64@4.2.4':
+    resolution: {integrity: sha512-yPyUXn3yO/ufR6+Kzv0t4fCg2qNr90jxXc5QqBpjlPNd0NqyDXcmQb/6weunH/MEDXW5dhyEi+agTDiqa3WsGg==}
     engines: {node: '>= 20'}
     cpu: [x64]
     os: [darwin]
 
-  '@tailwindcss/oxide-freebsd-x64@4.2.2':
-    resolution: {integrity: sha512-YUqUgrGMSu2CDO82hzlQ5qSb5xmx3RUrke/QgnoEx7KvmRJHQuZHZmZTLSuuHwFf0DJPybFMXMYf+WJdxHy/nQ==}
+  '@tailwindcss/oxide-freebsd-x64@4.2.4':
+    resolution: {integrity: sha512-BoMIB4vMQtZsXdGLVc2z+P9DbETkiopogfWZKbWwM8b/1Vinbs4YcUwo+kM/KeLkX3Ygrf4/PsRndKaYhS8Eiw==}
     engines: {node: '>= 20'}
     cpu: [x64]
     os: [freebsd]
 
-  '@tailwindcss/oxide-linux-arm-gnueabihf@4.2.2':
-    resolution: {integrity: sha512-FPdhvsW6g06T9BWT0qTwiVZYE2WIFo2dY5aCSpjG/S/u1tby+wXoslXS0kl3/KXnULlLr1E3NPRRw0g7t2kgaQ==}
+  '@tailwindcss/oxide-linux-arm-gnueabihf@4.2.4':
+    resolution: {integrity: sha512-7pIHBLTHYRAlS7V22JNuTh33yLH4VElwKtB3bwchK/UaKUPpQ0lPQiOWcbm4V3WP2I6fNIJ23vABIvoy2izdwA==}
     engines: {node: '>= 20'}
     cpu: [arm]
     os: [linux]
 
-  '@tailwindcss/oxide-linux-arm64-gnu@4.2.2':
-    resolution: {integrity: sha512-4og1V+ftEPXGttOO7eCmW7VICmzzJWgMx+QXAJRAhjrSjumCwWqMfkDrNu1LXEQzNAwz28NCUpucgQPrR4S2yw==}
+  '@tailwindcss/oxide-linux-arm64-gnu@4.2.4':
+    resolution: {integrity: sha512-+E4wxJ0ZGOzSH325reXTWB48l42i93kQqMvDyz5gqfRzRZ7faNhnmvlV4EPGJU3QJM/3Ab5jhJ5pCRUsKn6OQw==}
     engines: {node: '>= 20'}
     cpu: [arm64]
     os: [linux]
     libc: [glibc]
 
-  '@tailwindcss/oxide-linux-arm64-musl@4.2.2':
-    resolution: {integrity: sha512-oCfG/mS+/+XRlwNjnsNLVwnMWYH7tn/kYPsNPh+JSOMlnt93mYNCKHYzylRhI51X+TbR+ufNhhKKzm6QkqX8ag==}
+  '@tailwindcss/oxide-linux-arm64-musl@4.2.4':
+    resolution: {integrity: sha512-bBADEGAbo4ASnppIziaQJelekCxdMaxisrk+fB7Thit72IBnALp9K6ffA2G4ruj90G9XRS2VQ6q2bCKbfFV82g==}
     engines: {node: '>= 20'}
     cpu: [arm64]
     os: [linux]
     libc: [musl]
 
-  '@tailwindcss/oxide-linux-x64-gnu@4.2.2':
-    resolution: {integrity: sha512-rTAGAkDgqbXHNp/xW0iugLVmX62wOp2PoE39BTCGKjv3Iocf6AFbRP/wZT/kuCxC9QBh9Pu8XPkv/zCZB2mcMg==}
+  '@tailwindcss/oxide-linux-x64-gnu@4.2.4':
+    resolution: {integrity: sha512-7Mx25E4WTfnht0TVRTyC00j3i0M+EeFe7wguMDTlX4mRxafznw0CA8WJkFjWYH5BlgELd1kSjuU2JiPnNZbJDA==}
     engines: {node: '>= 20'}
     cpu: [x64]
     os: [linux]
     libc: [glibc]
 
-  '@tailwindcss/oxide-linux-x64-musl@4.2.2':
-    resolution: {integrity: sha512-XW3t3qwbIwiSyRCggeO2zxe3KWaEbM0/kW9e8+0XpBgyKU4ATYzcVSMKteZJ1iukJ3HgHBjbg9P5YPRCVUxlnQ==}
+  '@tailwindcss/oxide-linux-x64-musl@4.2.4':
+    resolution: {integrity: sha512-2wwJRF7nyhOR0hhHoChc04xngV3iS+akccHTGtz965FwF0up4b2lOdo6kI1EbDaEXKgvcrFBYcYQQ/rrnWFVfA==}
     engines: {node: '>= 20'}
     cpu: [x64]
     os: [linux]
     libc: [musl]
 
-  '@tailwindcss/oxide-wasm32-wasi@4.2.2':
-    resolution: {integrity: sha512-eKSztKsmEsn1O5lJ4ZAfyn41NfG7vzCg496YiGtMDV86jz1q/irhms5O0VrY6ZwTUkFy/EKG3RfWgxSI3VbZ8Q==}
+  '@tailwindcss/oxide-wasm32-wasi@4.2.4':
+    resolution: {integrity: sha512-FQsqApeor8Fo6gUEklzmaa9994orJZZDBAlQpK2Mq+DslRKFJeD6AjHpBQ0kZFQohVr8o85PPh8eOy86VlSCmw==}
     engines: {node: '>=14.0.0'}
     cpu: [wasm32]
     bundledDependencies:
@@ -664,24 +664,24 @@ packages:
       - '@emnapi/wasi-threads'
       - tslib
 
-  '@tailwindcss/oxide-win32-arm64-msvc@4.2.2':
-    resolution: {integrity: sha512-qPmaQM4iKu5mxpsrWZMOZRgZv1tOZpUm+zdhhQP0VhJfyGGO3aUKdbh3gDZc/dPLQwW4eSqWGrrcWNBZWUWaXQ==}
+  '@tailwindcss/oxide-win32-arm64-msvc@4.2.4':
+    resolution: {integrity: sha512-L9BXqxC4ToVgwMFqj3pmZRqyHEztulpUJzCxUtLjobMCzTPsGt1Fa9enKbOpY2iIyVtaHNeNvAK8ERP/64sqGQ==}
     engines: {node: '>= 20'}
     cpu: [arm64]
     os: [win32]
 
-  '@tailwindcss/oxide-win32-x64-msvc@4.2.2':
-    resolution: {integrity: sha512-1T/37VvI7WyH66b+vqHj/cLwnCxt7Qt3WFu5Q8hk65aOvlwAhs7rAp1VkulBJw/N4tMirXjVnylTR72uI0HGcA==}
+  '@tailwindcss/oxide-win32-x64-msvc@4.2.4':
+    resolution: {integrity: sha512-ESlKG0EpVJQwRjXDDa9rLvhEAh0mhP1sF7sap9dNZT0yyl9SAG6T7gdP09EH0vIv0UNTlo6jPWyujD6559fZvw==}
     engines: {node: '>= 20'}
     cpu: [x64]
     os: [win32]
 
-  '@tailwindcss/oxide@4.2.2':
-    resolution: {integrity: sha512-qEUA07+E5kehxYp9BVMpq9E8vnJuBHfJEC0vPC5e7iL/hw7HR61aDKoVoKzrG+QKp56vhNZe4qwkRmMC0zDLvg==}
+  '@tailwindcss/oxide@4.2.4':
+    resolution: {integrity: sha512-9El/iI069DKDSXwTvB9J4BwdO5JhRrOweGaK25taBAvBXyXqJAX+Jqdvs8r8gKpsI/1m0LeJLyQYTf/WLrBT1Q==}
     engines: {node: '>= 20'}
 
-  '@tailwindcss/vite@4.2.2':
-    resolution: {integrity: sha512-mEiF5HO1QqCLXoNEfXVA1Tzo+cYsrqV7w9Juj2wdUFyW07JRenqMG225MvPwr3ZD9N1bFQj46X7r33iHxLUW0w==}
+  '@tailwindcss/vite@4.2.4':
+    resolution: {integrity: sha512-pCvohwOCspk3ZFn6eJzrrX3g4n2JY73H6MmYC87XfGPyTty4YsCjYTMArRZm/zOI8dIt3+EcrLHAFPe5A4bgtw==}
     peerDependencies:
       vite: ^5.2.0 || ^6 || ^7 || ^8
 
@@ -709,8 +709,8 @@ packages:
   '@types/nlcst@2.0.3':
     resolution: {integrity: sha512-vSYNSDe6Ix3q+6Z7ri9lyWqgGhJTmzRjZRqyq15N0Z/1/UnVsno9G/N40NBijoYx2seFDIl0+B2mgAb9mezUCA==}
 
-  '@types/node@24.12.0':
-    resolution: {integrity: sha512-GYDxsZi3ChgmckRT9HPU0WEhKLP08ev/Yfcq2AstjrDASOYCSXeyjDsHg4v5t4jOj7cyDX3vmprafKlWIG9MXQ==}
+  '@types/node@24.12.2':
+    resolution: {integrity: sha512-A1sre26ke7HDIuY/M23nd9gfB+nrmhtYyMINbjI1zHJxYteKR6qSMX56FsmjMcDb3SMcjJg5BiRRgOCC/yBD0g==}
 
   '@types/sax@1.2.7':
     resolution: {integrity: sha512-rO73L89PJxeYM3s3pPPjiPgVVcymqU490g0YO5n5By0k2Erzj6tay/4lr1CHAAU4JyOWd1rpQ8bCf6cZfHU96A==}
@@ -768,8 +768,8 @@ packages:
     resolution: {integrity: sha512-LElXdjswlqjWrPpJFg1Fx4wpkOCxj1TDHlSV4PlaRxHGWko024xICaa97ZkMfs6DRKlCguiAI+rbXv5GWwXIkg==}
     hasBin: true
 
-  astro@6.1.1:
-    resolution: {integrity: sha512-vq8sHpu1JsY1fWAunn+tdKNbVDmLQNiVdyuGsVT2csgITdFGXXVAyEXFWc1DzkMN0ehElPeiHnqItyQOJK+GqA==}
+  astro@6.1.9:
+    resolution: {integrity: sha512-NsAHzMzpznB281g2aM5qnBt2QjfH6ttKiZ3hSZw52If8JJ+62kbnBKbyKhR2glQcJLl7Jfe4GSl0DihFZ36rRQ==}
     engines: {node: '>=22.12.0', npm: '>=9.6.5', pnpm: '>=7.1.0'}
     hasBin: true
 
@@ -824,8 +824,8 @@ packages:
     resolution: {integrity: sha512-dnN3ibLeoRf2HNC+OlCiNc5d2zxbLJXOtiZUudNFSXZrNSydxcCsSpRzXwfu7BBWCIfHPw+xTayeBvJCP/D8Ng==}
     engines: {node: '>= 18'}
 
-  cookie-es@1.2.2:
-    resolution: {integrity: sha512-+W7VmiVINB+ywl1HGXJXmrqkOhpKrIiVZV6tQuV54ZyQC7MMuBt81Vc336GMLoHBq5hV/F9eXgt5Mnx0Rha5Fg==}
+  cookie-es@1.2.3:
+    resolution: {integrity: sha512-lXVyvUvrNXblMqzIRrxHb57UUVmqsSWlxqt3XIjCkUP0wDAf6uicO6KMbEgYrMNtEvWgWHwe42CKxPu9MYAnWw==}
 
   cookie@1.1.1:
     resolution: {integrity: sha512-ei8Aos7ja0weRpFzJnEA9UHJ/7XQmqglbRwnf2ATjcB9Wq874VKH9kfjjirM6UhU2/E5fFYadylyhFldcqSidQ==}
@@ -865,8 +865,8 @@ packages:
   decode-named-character-reference@1.3.0:
     resolution: {integrity: sha512-GtpQYB283KrPp6nRw50q3U9/VfOutZOe103qlN7BPP6Ad27xYnOIWv4lPzo8HCAL+mMZofJ9KEy30fq6MfaK6Q==}
 
-  defu@6.1.4:
-    resolution: {integrity: sha512-mEQCMmwJu317oSz8CwdIOdwf3xMif1ttiM8LTufzc3g6kR+9Pe236twL8j3IYT1F7GfRgGcW6MWxzZjLIkuHIg==}
+  defu@6.1.7:
+    resolution: {integrity: sha512-7z22QmUWiQ/2d0KkdYmANbRUVABpZ9SNYyH5vx6PZ+nE5bcC0l7uFvEfHlyld/HcGBFTL536ClDt3DEcSlEJAQ==}
 
   dequal@2.0.3:
     resolution: {integrity: sha512-0je+qPKHEMohvfRTCEo3CrPG6cAzAYgmzKyxRiYSSDkS6eGJdyVJm7WaYA5ECaAD9wLB2T4EEeymA5aFVcYXCA==}
@@ -879,8 +879,8 @@ packages:
     resolution: {integrity: sha512-Btj2BOOO83o3WyH59e8MgXsxEQVcarkUOpEYrubB0urwnN10yQ364rsiByU11nZlqWYZm05i/of7io4mzihBtQ==}
     engines: {node: '>=8'}
 
-  devalue@5.6.4:
-    resolution: {integrity: sha512-Gp6rDldRsFh/7XuouDbxMH3Mx8GMCcgzIb1pDTvNyn8pZGQ22u+Wa+lGV9dQCltFQ7uVw0MhRyb8XDskNFOReA==}
+  devalue@5.7.1:
+    resolution: {integrity: sha512-MUbZ586EgQqdRnC4yDrlod3BEdyvE4TapGYHMW2CiaW+KkkFmWEFqBUaLltEZCGi0iFXCEjRF0OjF0DV2QHjOA==}
 
   devlop@1.1.0:
     resolution: {integrity: sha512-RWmIqhcFf1lRYBvNmr7qTNuyCt/7/ns2jbpp1+PalgE/rDQcBT0fioSMUpJ93irlUhC5hrg4cYqe6U+0ImW0rA==}
@@ -909,8 +909,8 @@ packages:
     resolution: {integrity: sha512-2QF/g9/zTaPDc3BjNcVTGoBbXBgYfMTTceLaYcFJ/W9kggFUkhxD/hMEeuLKbugyef9SqAx8cpgwlIP/jinUTA==}
     engines: {node: '>=4'}
 
-  enhanced-resolve@5.20.1:
-    resolution: {integrity: sha512-Qohcme7V1inbAfvjItgw0EaxVX5q2rdVEZHRBrEQdRZTssLDGsL8Lwrznl8oQ/6kuTJONLaDcGjkNP247XEhcA==}
+  enhanced-resolve@5.21.0:
+    resolution: {integrity: sha512-otxSQPw4lkOZWkHpB3zaEQs6gWYEsmX4xQF68ElXC/TWvGxGMSGOvoNbaLXm6/cS/fSfHtsEdw90y20PCd+sCA==}
     engines: {node: '>=10.13.0'}
 
   entities@4.5.0:
@@ -921,8 +921,8 @@ packages:
     resolution: {integrity: sha512-aN97NXWF6AWBTahfVOIrB/NShkzi5H7F9r1s9mD3cDj4Ko5f2qhhVoYMibXF7GlLveb/D2ioWay8lxI97Ven3g==}
     engines: {node: '>=0.12'}
 
-  es-module-lexer@2.0.0:
-    resolution: {integrity: sha512-5POEcUuZybH7IdmGsD8wlf0AI55wMecM9rVBTI/qEAy2c1kTOm3DjFYjrBdI2K3BaJjJYfYFeRtM0t9ssnRuxw==}
+  es-module-lexer@2.1.0:
+    resolution: {integrity: sha512-n27zTYMjYu1aj4MjCWzSP7G9r75utsaoc8m61weK+W8JMBGGQybd43GstCXZ3WNmSFtGT9wi59qQTW6mhTR5LQ==}
 
   esast-util-from-estree@2.0.0:
     resolution: {integrity: sha512-4CyanoAudUSBAn5K13H4JhsMH6L9ZP7XbLVe/dKybkxMO7eDyLsT8UHl9TRNrU2Gr9nz+FovfSIjuXWJ81uVwQ==}
@@ -930,8 +930,8 @@ packages:
   esast-util-from-js@2.0.1:
     resolution: {integrity: sha512-8Ja+rNJ0Lt56Pcf3TAmpBZjmx8ZcK5Ts4cAzIOjsjevg9oSXJnl6SUQ2EevU8tv3h6ZLWmoKL5H4fgWvdvfETw==}
 
-  esbuild@0.27.4:
-    resolution: {integrity: sha512-Rq4vbHnYkK5fws5NF7MYTU68FPRE1ajX7heQ/8QXXWqNgqqJ/GkmmyxIzUnf2Sr/bakf8l54716CcMGHYhMrrQ==}
+  esbuild@0.27.7:
+    resolution: {integrity: sha512-IxpibTjyVnmrIQo5aqNpCgoACA/dTKLTlhMHihVHhdkxKyPO1uBBthumT0rdHmcsk9uMonIWS0m4FljWzILh3w==}
     engines: {node: '>=18'}
     hasBin: true
 
@@ -969,6 +969,15 @@ packages:
   extend@3.0.2:
     resolution: {integrity: sha512-fjquC59cD7CyW6urNXK0FBufkZcoiGG80wTuPujX590cB5Ttln20E2UB4S/WARVqhXffZl2LNgS+gQdPIIim/g==}
 
+  fast-string-truncated-width@1.2.1:
+    resolution: {integrity: sha512-Q9acT/+Uu3GwGj+5w/zsGuQjh9O1TyywhIwAxHudtWrgF09nHOPrvTLhQevPbttcxjr/SNN7mJmfOw/B1bXgow==}
+
+  fast-string-width@1.1.0:
+    resolution: {integrity: sha512-O3fwIVIH5gKB38QNbdg+3760ZmGz0SZMgvwJbA1b2TGXceKE6A2cOlfogh1iw8lr049zPyd7YADHy+B7U4W9bQ==}
+
+  fast-wrap-ansi@0.1.6:
+    resolution: {integrity: sha512-HlUwET7a5gqjURj70D5jl7aC3Zmy4weA1SHUfM0JFI0Ptq987NH2TwbBFLoERhfwk+E+eaq4EK3jXoT+R3yp3w==}
+
   fdir@6.5.0:
     resolution: {integrity: sha512-tIbYtZbucOs0BRGqPJkshJUYdL+SDH7dVM8gjy+ERp3WAUjLEFJE+02kanyHtwjWOnwrKYBiwAmM0p4kLJAnXg==}
     engines: {node: '>=12.0.0'}
@@ -1000,8 +1009,8 @@ packages:
   graceful-fs@4.2.11:
     resolution: {integrity: sha512-RbJ5/jmFcNNCcDV5o9eTnBLJ/HszWV0P73bc+Ff4nS/rJj+YaS6IGyiOL0VoBYX+l1Wrl3k63h/KrH+nhJ0XvQ==}
 
-  h3@1.15.10:
-    resolution: {integrity: sha512-YzJeWSkDZxAhvmp8dexjRK5hxziRO7I9m0N53WhvYL5NiWfkUkzssVzY9jvGu0HBoLFW6+duYmNSn6MaZBCCtg==}
+  h3@1.15.11:
+    resolution: {integrity: sha512-L3THSe2MPeBwgIZVSH5zLdBBU90TOxarvhK9d04IDY2AmVS8j2Jz2LIWtwsGOU3lu2I5jCN7FNvVfY2+XyF+mg==}
 
   hast-util-from-html@2.0.3:
     resolution: {integrity: sha512-CUSRHXyKjzHov8yKsQjGOElXy/3EKpyX56ELnkHH34vDVw1N1XSQ1ZcAvTyAPtGqLTuKP/uxM+aLkSPqF/EtMw==}
@@ -1068,6 +1077,11 @@ packages:
     engines: {node: ^12.20.0 || ^14.13.1 || >=16.0.0}
     hasBin: true
 
+  is-docker@4.0.0:
+    resolution: {integrity: sha512-LHE+wROyG/Y/0ZnbktRCoTix2c1RhgWaZraMZ8o1Q7zCh0VSrICJQO5oqIIISrcSBtrXv0o233w1IYwsWCjTzA==}
+    engines: {node: '>=20'}
+    hasBin: true
+
   is-hexadecimal@2.0.1:
     resolution: {integrity: sha512-DgZQp241c8oO6cA1SbTEWiXeoxV42vlcJxgH+B3hi1AiqqKruZR3ZGF8In3fj4+/y/7rHvlOZLZtgJ/4ttYGZg==}
 
@@ -1169,8 +1183,8 @@ packages:
   longest-streak@3.1.0:
     resolution: {integrity: sha512-9Ri+o0JYgehTaVBBDoMqIl8GXtbWg711O3srftcHhZ0dqnETqLaoIK0x17fUw9rFSlK/0NlsKe0Ahhyl5pXE2g==}
 
-  lru-cache@11.2.7:
-    resolution: {integrity: sha512-aY/R+aEsRelme17KGQa/1ZSIpLpNYYrhcrepKTZgE+W3WM16YMCaPwOHLHsmopZHELU0Ojin1lPVxKR0MihncA==}
+  lru-cache@11.3.5:
+    resolution: {integrity: sha512-NxVFwLAnrd9i7KUBxC4DrUhmgjzOs+1Qm50D3oF1/oL+r1NpZ4gA7xvG0/zJ8evR7zIKn4vLf7qTNduWFtCrRw==}
     engines: {node: 20 || >=22}
 
   magic-string@0.30.21:
@@ -1389,18 +1403,18 @@ packages:
   ohash@2.0.11:
     resolution: {integrity: sha512-RdR9FQrFwNBNXAr4GixM8YaRZRJ5PUWbKYbE5eOsrwAjJW0q2REGcf79oYPsLyskQCZG1PLN+S/K1V00joZAoQ==}
 
-  oniguruma-parser@0.12.1:
-    resolution: {integrity: sha512-8Unqkvk1RYc6yq2WBYRj4hdnsAxVze8i7iPfQr8e4uSP3tRv0rpZcbGUDvxfQQcdwHt/e9PrMvGCsa8OqG9X3w==}
+  oniguruma-parser@0.12.2:
+    resolution: {integrity: sha512-6HVa5oIrgMC6aA6WF6XyyqbhRPJrKR02L20+2+zpDtO5QAzGHAUGw5TKQvwi5vctNnRHkJYmjAhRVQF2EKdTQw==}
 
-  oniguruma-to-es@4.3.5:
-    resolution: {integrity: sha512-Zjygswjpsewa0NLTsiizVuMQZbp0MDyM6lIt66OxsF21npUDlzpHi1Mgb/qhQdkb+dWFTzJmFbEWdvZgRho8eQ==}
+  oniguruma-to-es@4.3.6:
+    resolution: {integrity: sha512-csuQ9x3Yr0cEIs/Zgx/OEt9iBw9vqIunAPQkx19R/fiMq2oGVTgcMqO/V3Ybqefr1TBvosI6jU539ksaBULJyA==}
 
   p-limit@7.3.0:
     resolution: {integrity: sha512-7cIXg/Z0M5WZRblrsOla88S4wAK+zOQQWeBYfV3qJuJXMr+LnbYjaadrFaS0JILfEDPVqHyKnZ1Z/1d6J9VVUw==}
     engines: {node: '>=20'}
 
-  p-queue@9.1.0:
-    resolution: {integrity: sha512-O/ZPaXuQV29uSLbxWBGGZO1mCQXV2BLIwUr59JUU9SoH76mnYvtms7aafH/isNSNGwuEfP6W/4xD0/TJXxrizw==}
+  p-queue@9.1.2:
+    resolution: {integrity: sha512-ktsDOALzTYTWWF1PbkNVg2rOt+HaOaMWJMUnt7T3qf5tvZ1L8dBW3tObzprBcXNMKkwj+yFSLqHso0x+UFcJXw==}
     engines: {node: '>=20'}
 
   p-timeout@7.0.1:
@@ -1433,8 +1447,8 @@ packages:
     resolution: {integrity: sha512-QP88BAKvMam/3NxH6vj2o21R6MjxZUAd6nlwAS/pnGvN9IVLocLHxGYIzFhg6fUQ+5th6P4dv4eW9jX3DSIj7A==}
     engines: {node: '>=12'}
 
-  postcss@8.5.8:
-    resolution: {integrity: sha512-OW/rX8O/jXnm82Ey1k44pObPtdblfiuWnrd8X7GJ7emImCOstunGbXUpp7HdBrFQX6rJzn3sPT397Wp5aCwCHg==}
+  postcss@8.5.10:
+    resolution: {integrity: sha512-pMMHxBOZKFU6HgAZ4eyGnwXF/EvPGGqUr0MnZ5+99485wwW41kW91A4LOGxSHhgugZmSChL5AlElNdwlNgcnLQ==}
     engines: {node: ^10 || ^12 || >=14}
 
   prismjs@1.30.0:
@@ -1520,8 +1534,8 @@ packages:
   retext@9.0.0:
     resolution: {integrity: sha512-sbMDcpHCNjvlheSgMfEcVrZko3cDzdbe1x/e7G66dFp0Ff7Mldvi2uv6JkJQzdRcvLYE8CA8Oe8siQx8ZOgTcA==}
 
-  rollup@4.60.0:
-    resolution: {integrity: sha512-yqjxruMGBQJ2gG4HtjZtAfXArHomazDHoFwFFmZZl0r7Pdo7qCIXKqKHZc8yeoMgzJJ+pO6pEEHa+V7uzWlrAQ==}
+  rollup@4.60.2:
+    resolution: {integrity: sha512-J9qZyW++QK/09NyN/zeO0dG/1GdGfyp9lV8ajHnRVLfo/uFsbji5mHnDgn/qYdUHyCkM2N+8VyspgZclfAh0eQ==}
     engines: {node: '>=18.0.0', npm: '>=8.0.0'}
     hasBin: true
 
@@ -1582,11 +1596,11 @@ packages:
     engines: {node: '>=16'}
     hasBin: true
 
-  tailwindcss@4.2.2:
-    resolution: {integrity: sha512-KWBIxs1Xb6NoLdMVqhbhgwZf2PGBpPEiwOqgI4pFIYbNTfBXiKYyWoTsXgBQ9WFg/OlhnvHaY+AEpW7wSmFo2Q==}
+  tailwindcss@4.2.4:
+    resolution: {integrity: sha512-HhKppgO81FQof5m6TEnuBWCZGgfRAWbaeOaGT00KOy/Pf/j6oUihdvBpA7ltCeAvZpFhW3j0PTclkxsd4IXYDA==}
 
-  tapable@2.3.2:
-    resolution: {integrity: sha512-1MOpMXuhGzGL5TTCZFItxCc0AARf1EZFQkGqMm7ERKj8+Hgr5oLvJOVFcC+lRmR8hCe2S3jC4T5D7Vg/d7/fhA==}
+  tapable@2.3.3:
+    resolution: {integrity: sha512-uxc/zpqFg6x7C8vOE7lh6Lbda8eEL9zmVm/PLeTPBRhh1xCgdWaQ+J1CUieGpIfm2HdtsUpRv+HshiasBMcc6A==}
     engines: {node: '>=6'}
 
   tiny-inflate@1.0.3:
@@ -1596,12 +1610,12 @@ packages:
     resolution: {integrity: sha512-Ae3OVUqifDw0wBriIBS7yVaW44Dp6eSHQcyq4Igc7eN2TJH/2YsicswaW+J/OuMvhpDPOKEgpAZCjkb4hpoyeA==}
     engines: {node: ^16.14.0 || >= 17.3.0}
 
-  tinyexec@1.0.4:
-    resolution: {integrity: sha512-u9r3uZC0bdpGOXtlxUIdwf9pkmvhqJdrVCH9fapQtgy/OeTTMZ1nqH7agtvEfmGui6e1XxjcdrlxvxJvc3sMqw==}
+  tinyexec@1.1.1:
+    resolution: {integrity: sha512-VKS/ZaQhhkKFMANmAOhhXVoIfBXblQxGX1myCQ2faQrfmobMftXeJPcZGp0gS07ocvGJWDLZGyOZDadDBqYIJg==}
     engines: {node: '>=18'}
 
-  tinyglobby@0.2.15:
-    resolution: {integrity: sha512-j2Zq4NyQYG5XMST4cbs02Ak8iJUdxRM0XI5QyxXuZOzKOINmWurp3smXu3y5wDcJrptwpSjgXHzIQxR0omXljQ==}
+  tinyglobby@0.2.16:
+    resolution: {integrity: sha512-pn99VhoACYR8nFHhxqix+uvsbXineAasWm5ojXoN8xEwK5Kd3/TrhNn1wByuD52UxWRLy8pu+kRMniEi6Eq9Zg==}
     engines: {node: '>=12.0.0'}
 
   trim-lines@3.0.1:
@@ -1742,8 +1756,8 @@ packages:
   vfile@6.0.3:
     resolution: {integrity: sha512-KzIbH/9tXat2u30jf+smMwFCsno4wHVdNmzFyL+T/L3UGqqk6JKfVqOFOZEpZSHADH1k40ab6NUIXZq422ov3Q==}
 
-  vite@7.3.1:
-    resolution: {integrity: sha512-w+N7Hifpc3gRjZ63vYBXA56dvvRlNWRczTdmCBBa+CotUzAPf5b7YMdMR/8CQoeYE5LX3W4wj6RYTgonm1b9DA==}
+  vite@7.3.2:
+    resolution: {integrity: sha512-Bby3NOsna2jsjfLVOHKes8sGwgl4TT0E6vvpYgnAYDIF/tie7MRaFthmKuHx1NSXjiTueXH3do80FMQgvEktRg==}
     engines: {node: ^20.19.0 || >=22.12.0}
     hasBin: true
     peerDependencies:
@@ -1782,10 +1796,10 @@ packages:
       yaml:
         optional: true
 
-  vitefu@1.1.2:
-    resolution: {integrity: sha512-zpKATdUbzbsycPFBN71nS2uzBUQiVnFoOrr2rvqv34S1lcAgMKKkjWleLGeiJlZ8lwCXvtWaRn7R3ZC16SYRuw==}
+  vitefu@1.1.3:
+    resolution: {integrity: sha512-ub4okH7Z5KLjb6hDyjqrGXqWtWvoYdU3IGm/NorpgHncKoLTCfRIbvlhBm7r0YstIaQRYlp4yEbFqDcKSzXSSg==}
     peerDependencies:
-      vite: ^3.0.0 || ^4.0.0 || ^5.0.0 || ^6.0.0 || ^7.0.0 || ^8.0.0-beta.0
+      vite: ^3.0.0 || ^4.0.0 || ^5.0.0 || ^6.0.0 || ^7.0.0 || ^8.0.0
     peerDependenciesMeta:
       vite:
         optional: true
@@ -1818,13 +1832,13 @@ snapshots:
 
   '@astrojs/compiler@3.0.1': {}
 
-  '@astrojs/internal-helpers@0.8.0':
+  '@astrojs/internal-helpers@0.9.0':
     dependencies:
       picomatch: 4.0.4
 
-  '@astrojs/markdown-remark@7.1.0':
+  '@astrojs/markdown-remark@7.1.1':
     dependencies:
-      '@astrojs/internal-helpers': 0.8.0
+      '@astrojs/internal-helpers': 0.9.0
       '@astrojs/prism': 4.0.1
       github-slugger: 2.0.0
       hast-util-from-html: 2.0.3
@@ -1848,13 +1862,13 @@ snapshots:
     transitivePeerDependencies:
       - supports-color
 
-  '@astrojs/mdx@5.0.3(astro@6.1.1(@types/node@24.12.0)(@vercel/functions@3.4.3)(jiti@2.6.1)(lightningcss@1.32.0)(rollup@4.60.0))':
+  '@astrojs/mdx@5.0.4(astro@6.1.9(@types/node@24.12.2)(@vercel/functions@3.4.3)(jiti@2.6.1)(lightningcss@1.32.0)(rollup@4.60.2))':
     dependencies:
-      '@astrojs/markdown-remark': 7.1.0
+      '@astrojs/markdown-remark': 7.1.1
       '@mdx-js/mdx': 3.1.1
       acorn: 8.16.0
-      astro: 6.1.1(@types/node@24.12.0)(@vercel/functions@3.4.3)(jiti@2.6.1)(lightningcss@1.32.0)(rollup@4.60.0)
-      es-module-lexer: 2.0.0
+      astro: 6.1.9(@types/node@24.12.2)(@vercel/functions@3.4.3)(jiti@2.6.1)(lightningcss@1.32.0)(rollup@4.60.2)
+      es-module-lexer: 2.1.0
       estree-util-visit: 2.0.0
       hast-util-to-html: 9.0.5
       piccolore: 0.1.3
@@ -1877,17 +1891,14 @@ snapshots:
       stream-replace-string: 2.0.0
       zod: 4.3.6
 
-  '@astrojs/telemetry@3.3.0':
+  '@astrojs/telemetry@3.3.1':
     dependencies:
       ci-info: 4.4.0
-      debug: 4.4.3
       dlv: 1.1.3
       dset: 3.1.4
-      is-docker: 3.0.0
+      is-docker: 4.0.0
       is-wsl: 3.1.1
       which-pm-runs: 1.1.0
-    transitivePeerDependencies:
-      - supports-color
 
   '@babel/helper-string-parser@7.27.1': {}
 
@@ -1906,96 +1917,99 @@ snapshots:
     dependencies:
       fontkitten: 1.0.3
 
-  '@clack/core@1.1.0':
+  '@clack/core@1.2.0':
     dependencies:
+      fast-wrap-ansi: 0.1.6
       sisteransi: 1.0.5
 
-  '@clack/prompts@1.1.0':
+  '@clack/prompts@1.2.0':
     dependencies:
-      '@clack/core': 1.1.0
+      '@clack/core': 1.2.0
+      fast-string-width: 1.1.0
+      fast-wrap-ansi: 0.1.6
       sisteransi: 1.0.5
 
-  '@emnapi/runtime@1.9.1':
+  '@emnapi/runtime@1.10.0':
     dependencies:
       tslib: 2.8.1
     optional: true
 
-  '@esbuild/aix-ppc64@0.27.4':
+  '@esbuild/aix-ppc64@0.27.7':
     optional: true
 
-  '@esbuild/android-arm64@0.27.4':
+  '@esbuild/android-arm64@0.27.7':
     optional: true
 
-  '@esbuild/android-arm@0.27.4':
+  '@esbuild/android-arm@0.27.7':
     optional: true
 
-  '@esbuild/android-x64@0.27.4':
+  '@esbuild/android-x64@0.27.7':
     optional: true
 
-  '@esbuild/darwin-arm64@0.27.4':
+  '@esbuild/darwin-arm64@0.27.7':
     optional: true
 
-  '@esbuild/darwin-x64@0.27.4':
+  '@esbuild/darwin-x64@0.27.7':
     optional: true
 
-  '@esbuild/freebsd-arm64@0.27.4':
+  '@esbuild/freebsd-arm64@0.27.7':
     optional: true
 
-  '@esbuild/freebsd-x64@0.27.4':
+  '@esbuild/freebsd-x64@0.27.7':
     optional: true
 
-  '@esbuild/linux-arm64@0.27.4':
+  '@esbuild/linux-arm64@0.27.7':
     optional: true
 
-  '@esbuild/linux-arm@0.27.4':
+  '@esbuild/linux-arm@0.27.7':
     optional: true
 
-  '@esbuild/linux-ia32@0.27.4':
+  '@esbuild/linux-ia32@0.27.7':
     optional: true
 
-  '@esbuild/linux-loong64@0.27.4':
+  '@esbuild/linux-loong64@0.27.7':
     optional: true
 
-  '@esbuild/linux-mips64el@0.27.4':
+  '@esbuild/linux-mips64el@0.27.7':
     optional: true
 
-  '@esbuild/linux-ppc64@0.27.4':
+  '@esbuild/linux-ppc64@0.27.7':
     optional: true
 
-  '@esbuild/linux-riscv64@0.27.4':
+  '@esbuild/linux-riscv64@0.27.7':
     optional: true
 
-  '@esbuild/linux-s390x@0.27.4':
+  '@esbuild/linux-s390x@0.27.7':
     optional: true
 
-  '@esbuild/linux-x64@0.27.4':
+  '@esbuild/linux-x64@0.27.7':
     optional: true
 
-  '@esbuild/netbsd-arm64@0.27.4':
+  '@esbuild/netbsd-arm64@0.27.7':
     optional: true
 
-  '@esbuild/netbsd-x64@0.27.4':
+  '@esbuild/netbsd-x64@0.27.7':
     optional: true
 
-  '@esbuild/openbsd-arm64@0.27.4':
+  '@esbuild/openbsd-arm64@0.27.7':
     optional: true
 
-  '@esbuild/openbsd-x64@0.27.4':
+  '@esbuild/openbsd-x64@0.27.7':
     optional: true
 
-  '@esbuild/openharmony-arm64@0.27.4':
+  '@esbuild/openharmony-arm64@0.27.7':
     optional: true
 
-  '@esbuild/sunos-x64@0.27.4':
+  '@esbuild/sunos-x64@0.27.7':
     optional: true
 
-  '@esbuild/win32-arm64@0.27.4':
+  '@esbuild/win32-arm64@0.27.7':
     optional: true
 
-  '@esbuild/win32-ia32@0.27.4':
+  '@esbuild/win32-ia32@0.27.7':
     optional: true
 
-  '@esbuild/win32-x64@0.27.4':
+  '@esbuild/win32-x64@0.27.7':
     optional: true
 
   '@img/colour@1.1.0':
@@ -2083,7 +2097,7 @@ snapshots:
 
   '@img/sharp-wasm32@0.34.5':
     dependencies:
-      '@emnapi/runtime': 1.9.1
+      '@emnapi/runtime': 1.10.0
     optional: true
 
   '@img/sharp-win32-arm64@0.34.5':
@@ -2146,87 +2160,87 @@ snapshots:
 
   '@oslojs/encoding@1.1.0': {}
 
-  '@rollup/pluginutils@5.3.0(rollup@4.60.0)':
+  '@rollup/pluginutils@5.3.0(rollup@4.60.2)':
     dependencies:
       '@types/estree': 1.0.8
       estree-walker: 2.0.2
       picomatch: 4.0.4
     optionalDependencies:
-      rollup: 4.60.0
+      rollup: 4.60.2
 
-  '@rollup/rollup-android-arm-eabi@4.60.0':
+  '@rollup/rollup-android-arm-eabi@4.60.2':
     optional: true
 
-  '@rollup/rollup-android-arm64@4.60.0':
+  '@rollup/rollup-android-arm64@4.60.2':
     optional: true
 
-  '@rollup/rollup-darwin-arm64@4.60.0':
+  '@rollup/rollup-darwin-arm64@4.60.2':
     optional: true
 
-  '@rollup/rollup-darwin-x64@4.60.0':
+  '@rollup/rollup-darwin-x64@4.60.2':
     optional: true
 
-  '@rollup/rollup-freebsd-arm64@4.60.0':
+  '@rollup/rollup-freebsd-arm64@4.60.2':
     optional: true
 
-  '@rollup/rollup-freebsd-x64@4.60.0':
+  '@rollup/rollup-freebsd-x64@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-arm-gnueabihf@4.60.0':
+  '@rollup/rollup-linux-arm-gnueabihf@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-arm-musleabihf@4.60.0':
+  '@rollup/rollup-linux-arm-musleabihf@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-arm64-gnu@4.60.0':
+  '@rollup/rollup-linux-arm64-gnu@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-arm64-musl@4.60.0':
+  '@rollup/rollup-linux-arm64-musl@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-loong64-gnu@4.60.0':
+  '@rollup/rollup-linux-loong64-gnu@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-loong64-musl@4.60.0':
+  '@rollup/rollup-linux-loong64-musl@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-ppc64-gnu@4.60.0':
+  '@rollup/rollup-linux-ppc64-gnu@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-ppc64-musl@4.60.0':
+  '@rollup/rollup-linux-ppc64-musl@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-riscv64-gnu@4.60.0':
+  '@rollup/rollup-linux-riscv64-gnu@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-riscv64-musl@4.60.0':
+  '@rollup/rollup-linux-riscv64-musl@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-s390x-gnu@4.60.0':
+  '@rollup/rollup-linux-s390x-gnu@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-x64-gnu@4.60.0':
+  '@rollup/rollup-linux-x64-gnu@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-x64-musl@4.60.0':
+  '@rollup/rollup-linux-x64-musl@4.60.2':
     optional: true
 
-  '@rollup/rollup-openbsd-x64@4.60.0':
+  '@rollup/rollup-openbsd-x64@4.60.2':
     optional: true
 
-  '@rollup/rollup-openharmony-arm64@4.60.0':
+  '@rollup/rollup-openharmony-arm64@4.60.2':
     optional: true
 
-  '@rollup/rollup-win32-arm64-msvc@4.60.0':
+  '@rollup/rollup-win32-arm64-msvc@4.60.2':
     optional: true
 
-  '@rollup/rollup-win32-ia32-msvc@4.60.0':
+  '@rollup/rollup-win32-ia32-msvc@4.60.2':
     optional: true
 
-  '@rollup/rollup-win32-x64-gnu@4.60.0':
+  '@rollup/rollup-win32-x64-gnu@4.60.2':
     optional: true
 
-  '@rollup/rollup-win32-x64-msvc@4.60.0':
+  '@rollup/rollup-win32-x64-msvc@4.60.2':
     optional: true
 
   '@shikijs/core@4.0.2':
@@ -2241,7 +2255,7 @@ snapshots:
     dependencies:
       '@shikijs/types': 4.0.2
       '@shikijs/vscode-textmate': 10.0.2
-      oniguruma-to-es: 4.3.5
+      oniguruma-to-es: 4.3.6
 
   '@shikijs/engine-oniguruma@4.0.2':
     dependencies:
@@ -2269,73 +2283,73 @@ snapshots:
 
   '@shikijs/vscode-textmate@10.0.2': {}
 
-  '@tailwindcss/node@4.2.2':
+  '@tailwindcss/node@4.2.4':
     dependencies:
       '@jridgewell/remapping': 2.3.5
-      enhanced-resolve: 5.20.1
+      enhanced-resolve: 5.21.0
       jiti: 2.6.1
       lightningcss: 1.32.0
       magic-string: 0.30.21
       source-map-js: 1.2.1
-      tailwindcss: 4.2.2
+      tailwindcss: 4.2.4
 
-  '@tailwindcss/oxide-android-arm64@4.2.2':
+  '@tailwindcss/oxide-android-arm64@4.2.4':
     optional: true
 
-  '@tailwindcss/oxide-darwin-arm64@4.2.2':
+  '@tailwindcss/oxide-darwin-arm64@4.2.4':
     optional: true
 
-  '@tailwindcss/oxide-darwin-x64@4.2.2':
+  '@tailwindcss/oxide-darwin-x64@4.2.4':
     optional: true
 
-  '@tailwindcss/oxide-freebsd-x64@4.2.2':
+  '@tailwindcss/oxide-freebsd-x64@4.2.4':
     optional: true
 
-  '@tailwindcss/oxide-linux-arm-gnueabihf@4.2.2':
+  '@tailwindcss/oxide-linux-arm-gnueabihf@4.2.4':
     optional: true
 
-  '@tailwindcss/oxide-linux-arm64-gnu@4.2.2':
+  '@tailwindcss/oxide-linux-arm64-gnu@4.2.4':
     optional: true
 
-  '@tailwindcss/oxide-linux-arm64-musl@4.2.2':
+  '@tailwindcss/oxide-linux-arm64-musl@4.2.4':
     optional: true
 
-  '@tailwindcss/oxide-linux-x64-gnu@4.2.2':
+  '@tailwindcss/oxide-linux-x64-gnu@4.2.4':
     optional: true
 
-  '@tailwindcss/oxide-linux-x64-musl@4.2.2':
+  '@tailwindcss/oxide-linux-x64-musl@4.2.4':
     optional: true
 
-  '@tailwindcss/oxide-wasm32-wasi@4.2.2':
+  '@tailwindcss/oxide-wasm32-wasi@4.2.4':
     optional: true
 
-  '@tailwindcss/oxide-win32-arm64-msvc@4.2.2':
+  '@tailwindcss/oxide-win32-arm64-msvc@4.2.4':
     optional: true
 
-  '@tailwindcss/oxide-win32-x64-msvc@4.2.2':
+  '@tailwindcss/oxide-win32-x64-msvc@4.2.4':
     optional: true
 
-  '@tailwindcss/oxide@4.2.2':
+  '@tailwindcss/oxide@4.2.4':
     optionalDependencies:
-      '@tailwindcss/oxide-android-arm64': 4.2.2
-      '@tailwindcss/oxide-darwin-arm64': 4.2.2
-      '@tailwindcss/oxide-darwin-x64': 4.2.2
-      '@tailwindcss/oxide-freebsd-x64': 4.2.2
-      '@tailwindcss/oxide-linux-arm-gnueabihf': 4.2.2
-      '@tailwindcss/oxide-linux-arm64-gnu': 4.2.2
-      '@tailwindcss/oxide-linux-arm64-musl': 4.2.2
-      '@tailwindcss/oxide-linux-x64-gnu': 4.2.2
-      '@tailwindcss/oxide-linux-x64-musl': 4.2.2
-      '@tailwindcss/oxide-wasm32-wasi': 4.2.2
-      '@tailwindcss/oxide-win32-arm64-msvc': 4.2.2
-      '@tailwindcss/oxide-win32-x64-msvc': 4.2.2
-
-  '@tailwindcss/vite@4.2.2(vite@7.3.1(@types/node@24.12.0)(jiti@2.6.1)(lightningcss@1.32.0))':
-    dependencies:
-      '@tailwindcss/node': 4.2.2
-      '@tailwindcss/oxide': 4.2.2
-      tailwindcss: 4.2.2
-      vite: 7.3.1(@types/node@24.12.0)(jiti@2.6.1)(lightningcss@1.32.0)
+      '@tailwindcss/oxide-android-arm64': 4.2.4
+      '@tailwindcss/oxide-darwin-arm64': 4.2.4
+      '@tailwindcss/oxide-darwin-x64': 4.2.4
+      '@tailwindcss/oxide-freebsd-x64': 4.2.4
+      '@tailwindcss/oxide-linux-arm-gnueabihf': 4.2.4
+      '@tailwindcss/oxide-linux-arm64-gnu': 4.2.4
+      '@tailwindcss/oxide-linux-arm64-musl': 4.2.4
+      '@tailwindcss/oxide-linux-x64-gnu': 4.2.4
+      '@tailwindcss/oxide-linux-x64-musl': 4.2.4
+      '@tailwindcss/oxide-wasm32-wasi': 4.2.4
+      '@tailwindcss/oxide-win32-arm64-msvc': 4.2.4
+      '@tailwindcss/oxide-win32-x64-msvc': 4.2.4
+
+  '@tailwindcss/vite@4.2.4(vite@7.3.2(@types/node@24.12.2)(jiti@2.6.1)(lightningcss@1.32.0))':
+    dependencies:
+      '@tailwindcss/node': 4.2.4
+      '@tailwindcss/oxide': 4.2.4
+      tailwindcss: 4.2.4
+      vite: 7.3.2(@types/node@24.12.2)(jiti@2.6.1)(lightningcss@1.32.0)
 
   '@types/debug@4.1.13':
     dependencies:
@@ -2363,13 +2377,13 @@ snapshots:
     dependencies:
       '@types/unist': 3.0.3
 
-  '@types/node@24.12.0':
+  '@types/node@24.12.2':
     dependencies:
       undici-types: 7.16.0
 
   '@types/sax@1.2.7':
     dependencies:
-      '@types/node': 24.12.0
+      '@types/node': 24.12.2
 
   '@types/unist@2.0.11': {}
 
@@ -2406,28 +2420,27 @@ snapshots:
 
   astring@1.9.0: {}
 
-  astro@6.1.1(@types/node@24.12.0)(@vercel/functions@3.4.3)(jiti@2.6.1)(lightningcss@1.32.0)(rollup@4.60.0):
+  astro@6.1.9(@types/node@24.12.2)(@vercel/functions@3.4.3)(jiti@2.6.1)(lightningcss@1.32.0)(rollup@4.60.2):
     dependencies:
       '@astrojs/compiler': 3.0.1
-      '@astrojs/internal-helpers': 0.8.0
-      '@astrojs/markdown-remark': 7.1.0
-      '@astrojs/telemetry': 3.3.0
+      '@astrojs/internal-helpers': 0.9.0
+      '@astrojs/markdown-remark': 7.1.1
+      '@astrojs/telemetry': 3.3.1
       '@capsizecss/unpack': 4.0.0
-      '@clack/prompts': 1.1.0
+      '@clack/prompts': 1.2.0
       '@oslojs/encoding': 1.1.0
-      '@rollup/pluginutils': 5.3.0(rollup@4.60.0)
+      '@rollup/pluginutils': 5.3.0(rollup@4.60.2)
       aria-query: 5.3.2
       axobject-query: 4.1.0
       ci-info: 4.4.0
       clsx: 2.1.1
       common-ancestor-path: 2.0.0
       cookie: 1.1.1
-      devalue: 5.6.4
+      devalue: 5.7.1
       diff: 8.0.4
-      dlv: 1.1.3
       dset: 3.1.4
-      es-module-lexer: 2.0.0
-      esbuild: 0.27.4
+      es-module-lexer: 2.1.0
+      esbuild: 0.27.7
       flattie: 1.1.1
       fontace: 0.4.1
       github-slugger: 2.0.0
@@ -2440,7 +2453,7 @@ snapshots:
       neotraverse: 0.6.18
       obug: 2.1.1
       p-limit: 7.3.0
-      p-queue: 9.1.0
+      p-queue: 9.1.2
       package-manager-detector: 1.6.0
       piccolore: 0.1.3
       picomatch: 4.0.4
@@ -2450,16 +2463,16 @@ snapshots:
       smol-toml: 1.6.1
       svgo: 4.0.1
       tinyclip: 0.1.12
-      tinyexec: 1.0.4
-      tinyglobby: 0.2.15
+      tinyexec: 1.1.1
+      tinyglobby: 0.2.16
       tsconfck: 3.1.6
       ultrahtml: 1.6.0
       unifont: 0.7.4
       unist-util-visit: 5.1.0
       unstorage: 1.17.5(@vercel/functions@3.4.3)
       vfile: 6.0.3
-      vite: 7.3.1(@types/node@24.12.0)(jiti@2.6.1)(lightningcss@1.32.0)
-      vitefu: 1.1.2(vite@7.3.1(@types/node@24.12.0)(jiti@2.6.1)(lightningcss@1.32.0))
+      vite: 7.3.2(@types/node@24.12.2)(jiti@2.6.1)(lightningcss@1.32.0)
+      vitefu: 1.1.3(vite@7.3.2(@types/node@24.12.2)(jiti@2.6.1)(lightningcss@1.32.0))
       xxhash-wasm: 1.1.0
       yargs-parser: 22.0.0
       zod: 4.3.6
@@ -2532,7 +2545,7 @@ snapshots:
 
   common-ancestor-path@2.0.0: {}
 
-  cookie-es@1.2.2: {}
+  cookie-es@1.2.3: {}
 
   cookie@1.1.1: {}
 
@@ -2572,7 +2585,7 @@ snapshots:
     dependencies:
       character-entities: 2.0.2
 
-  defu@6.1.4: {}
+  defu@6.1.7: {}
 
   dequal@2.0.3: {}
 
@@ -2580,7 +2593,7 @@ snapshots:
 
   detect-libc@2.1.2: {}
 
-  devalue@5.6.4: {}
+  devalue@5.7.1: {}
 
   devlop@1.1.0:
     dependencies:
@@ -2610,16 +2623,16 @@ snapshots:
 
   dset@3.1.4: {}
 
-  enhanced-resolve@5.20.1:
+  enhanced-resolve@5.21.0:
     dependencies:
       graceful-fs: 4.2.11
-      tapable: 2.3.2
+      tapable: 2.3.3
 
   entities@4.5.0: {}
 
   entities@6.0.1: {}
 
-  es-module-lexer@2.0.0: {}
+  es-module-lexer@2.1.0: {}
 
   esast-util-from-estree@2.0.0:
     dependencies:
@@ -2635,34 +2648,34 @@ snapshots:
       esast-util-from-estree: 2.0.0
       vfile-message: 4.0.3
 
-  esbuild@0.27.4:
+  esbuild@0.27.7:
     optionalDependencies:
-      '@esbuild/aix-ppc64': 0.27.4
-      '@esbuild/android-arm': 0.27.4
-      '@esbuild/android-arm64': 0.27.4
-      '@esbuild/android-x64': 0.27.4
-      '@esbuild/darwin-arm64': 0.27.4
-      '@esbuild/darwin-x64': 0.27.4
-      '@esbuild/freebsd-arm64': 0.27.4
-      '@esbuild/freebsd-x64': 0.27.4
-      '@esbuild/linux-arm': 0.27.4
-      '@esbuild/linux-arm64': 0.27.4
-      '@esbuild/linux-ia32': 0.27.4
-      '@esbuild/linux-loong64': 0.27.4
-      '@esbuild/linux-mips64el': 0.27.4
-      '@esbuild/linux-ppc64': 0.27.4
-      '@esbuild/linux-riscv64': 0.27.4
-      '@esbuild/linux-s390x': 0.27.4
-      '@esbuild/linux-x64': 0.27.4
-      '@esbuild/netbsd-arm64': 0.27.4
-      '@esbuild/netbsd-x64': 0.27.4
-      '@esbuild/openbsd-arm64': 0.27.4
-      '@esbuild/openbsd-x64': 0.27.4
-      '@esbuild/openharmony-arm64': 0.27.4
-      '@esbuild/sunos-x64': 0.27.4
-      '@esbuild/win32-arm64': 0.27.4
-      '@esbuild/win32-ia32': 0.27.4
-      '@esbuild/win32-x64': 0.27.4
+      '@esbuild/aix-ppc64': 0.27.7
+      '@esbuild/android-arm': 0.27.7
+      '@esbuild/android-arm64': 0.27.7
+      '@esbuild/android-x64': 0.27.7
+      '@esbuild/darwin-arm64': 0.27.7
+      '@esbuild/darwin-x64': 0.27.7
+      '@esbuild/freebsd-arm64': 0.27.7
+      '@esbuild/freebsd-x64': 0.27.7
+      '@esbuild/linux-arm': 0.27.7
+      '@esbuild/linux-arm64': 0.27.7
+      '@esbuild/linux-ia32': 0.27.7
+      '@esbuild/linux-loong64': 0.27.7
+      '@esbuild/linux-mips64el': 0.27.7
+      '@esbuild/linux-ppc64': 0.27.7
+      '@esbuild/linux-riscv64': 0.27.7
+      '@esbuild/linux-s390x': 0.27.7
+      '@esbuild/linux-x64': 0.27.7
+      '@esbuild/netbsd-arm64': 0.27.7
+      '@esbuild/netbsd-x64': 0.27.7
+      '@esbuild/openbsd-arm64': 0.27.7
+      '@esbuild/openbsd-x64': 0.27.7
+      '@esbuild/openharmony-arm64': 0.27.7
+      '@esbuild/sunos-x64': 0.27.7
+      '@esbuild/win32-arm64': 0.27.7
+      '@esbuild/win32-ia32': 0.27.7
+      '@esbuild/win32-x64': 0.27.7
 
   escape-string-regexp@5.0.0: {}
 
@@ -2705,6 +2718,16 @@ snapshots:
 
   extend@3.0.2: {}
 
+  fast-string-truncated-width@1.2.1: {}
+
+  fast-string-width@1.1.0:
+    dependencies:
+      fast-string-truncated-width: 1.2.1
+
+  fast-wrap-ansi@0.1.6:
+    dependencies:
+      fast-string-width: 1.1.0
+
   fdir@6.5.0(picomatch@4.0.4):
     optionalDependencies:
       picomatch: 4.0.4
@@ -2726,11 +2749,11 @@ snapshots:
 
   graceful-fs@4.2.11: {}
 
-  h3@1.15.10:
+  h3@1.15.11:
     dependencies:
-      cookie-es: 1.2.2
+      cookie-es: 1.2.3
       crossws: 0.3.5
-      defu: 6.1.4
+      defu: 6.1.7
       destr: 2.0.5
       iron-webcrypto: 1.2.1
       node-mock-http: 1.0.4
@@ -2887,6 +2910,8 @@ snapshots:
 
   is-docker@3.0.0: {}
 
+  is-docker@4.0.0: {}
+
   is-hexadecimal@2.0.1: {}
 
   is-inside-container@1.0.0:
@@ -2956,7 +2981,7 @@ snapshots:
 
   longest-streak@3.1.0: {}
 
-  lru-cache@11.2.7: {}
+  lru-cache@11.3.5: {}
 
   magic-string@0.30.21:
     dependencies:
@@ -3441,11 +3466,11 @@ snapshots:
 
   ohash@2.0.11: {}
 
-  oniguruma-parser@0.12.1: {}
+  oniguruma-parser@0.12.2: {}
 
-  oniguruma-to-es@4.3.5:
+  oniguruma-to-es@4.3.6:
     dependencies:
-      oniguruma-parser: 0.12.1
+      oniguruma-parser: 0.12.2
       regex: 6.1.0
       regex-recursion: 6.0.2
 
@@ -3453,7 +3478,7 @@ snapshots:
     dependencies:
       yocto-queue: 1.2.2
 
-  p-queue@9.1.0:
+  p-queue@9.1.2:
     dependencies:
       eventemitter3: 5.0.4
       p-timeout: 7.0.1
@@ -3493,7 +3518,7 @@ snapshots:
 
   picomatch@4.0.4: {}
 
-  postcss@8.5.8:
+  postcss@8.5.10:
     dependencies:
       nanoid: 3.3.11
       picocolors: 1.1.1
@@ -3652,35 +3677,35 @@ snapshots:
       retext-stringify: 4.0.0
       unified: 11.0.5
 
-  rollup@4.60.0:
+  rollup@4.60.2:
     dependencies:
       '@types/estree': 1.0.8
     optionalDependencies:
-      '@rollup/rollup-android-arm-eabi': 4.60.0
-      '@rollup/rollup-android-arm64': 4.60.0
-      '@rollup/rollup-darwin-arm64': 4.60.0
-      '@rollup/rollup-darwin-x64': 4.60.0
-      '@rollup/rollup-freebsd-arm64': 4.60.0
-      '@rollup/rollup-freebsd-x64': 4.60.0
-      '@rollup/rollup-linux-arm-gnueabihf': 4.60.0
-      '@rollup/rollup-linux-arm-musleabihf': 4.60.0
-      '@rollup/rollup-linux-arm64-gnu': 4.60.0
-      '@rollup/rollup-linux-arm64-musl': 4.60.0
-      '@rollup/rollup-linux-loong64-gnu': 4.60.0
-      '@rollup/rollup-linux-loong64-musl': 4.60.0
-      '@rollup/rollup-linux-ppc64-gnu': 4.60.0
-      '@rollup/rollup-linux-ppc64-musl': 4.60.0
-      '@rollup/rollup-linux-riscv64-gnu': 4.60.0
-      '@rollup/rollup-linux-riscv64-musl': 4.60.0
-      '@rollup/rollup-linux-s390x-gnu': 4.60.0
-      '@rollup/rollup-linux-x64-gnu': 4.60.0
-      '@rollup/rollup-linux-x64-musl': 4.60.0
-      '@rollup/rollup-openbsd-x64': 4.60.0
-      '@rollup/rollup-openharmony-arm64': 4.60.0
-      '@rollup/rollup-win32-arm64-msvc': 4.60.0
-      '@rollup/rollup-win32-ia32-msvc': 4.60.0
-      '@rollup/rollup-win32-x64-gnu': 4.60.0
-      '@rollup/rollup-win32-x64-msvc': 4.60.0
+      '@rollup/rollup-android-arm-eabi': 4.60.2
+      '@rollup/rollup-android-arm64': 4.60.2
+      '@rollup/rollup-darwin-arm64': 4.60.2
+      '@rollup/rollup-darwin-x64': 4.60.2
+      '@rollup/rollup-freebsd-arm64': 4.60.2
+      '@rollup/rollup-freebsd-x64': 4.60.2
+      '@rollup/rollup-linux-arm-gnueabihf': 4.60.2
+      '@rollup/rollup-linux-arm-musleabihf': 4.60.2
+      '@rollup/rollup-linux-arm64-gnu': 4.60.2
+      '@rollup/rollup-linux-arm64-musl': 4.60.2
+      '@rollup/rollup-linux-loong64-gnu': 4.60.2
+      '@rollup/rollup-linux-loong64-musl': 4.60.2
+      '@rollup/rollup-linux-ppc64-gnu': 4.60.2
+      '@rollup/rollup-linux-ppc64-musl': 4.60.2
+      '@rollup/rollup-linux-riscv64-gnu': 4.60.2
+      '@rollup/rollup-linux-riscv64-musl': 4.60.2
+      '@rollup/rollup-linux-s390x-gnu': 4.60.2
+      '@rollup/rollup-linux-x64-gnu': 4.60.2
+      '@rollup/rollup-linux-x64-musl': 4.60.2
+      '@rollup/rollup-openbsd-x64': 4.60.2
+      '@rollup/rollup-openharmony-arm64': 4.60.2
+      '@rollup/rollup-win32-arm64-msvc': 4.60.2
+      '@rollup/rollup-win32-ia32-msvc': 4.60.2
+      '@rollup/rollup-win32-x64-gnu': 4.60.2
+      '@rollup/rollup-win32-x64-msvc': 4.60.2
       fsevents: 2.3.3
 
   sax@1.6.0: {}
@@ -3734,7 +3759,7 @@ snapshots:
 
   sitemap@9.0.1:
     dependencies:
-      '@types/node': 24.12.0
+      '@types/node': 24.12.2
       '@types/sax': 1.2.7
       arg: 5.0.2
       sax: 1.6.0
@@ -3772,17 +3797,17 @@ snapshots:
       picocolors: 1.1.1
       sax: 1.6.0
 
-  tailwindcss@4.2.2: {}
+  tailwindcss@4.2.4: {}
 
-  tapable@2.3.2: {}
+  tapable@2.3.3: {}
 
   tiny-inflate@1.0.3: {}
 
   tinyclip@0.1.12: {}
 
-  tinyexec@1.0.4: {}
+  tinyexec@1.1.1: {}
 
-  tinyglobby@0.2.15:
+  tinyglobby@0.2.16:
     dependencies:
       fdir: 6.5.0(picomatch@4.0.4)
       picomatch: 4.0.4
@@ -3871,8 +3896,8 @@ snapshots:
       anymatch: 3.1.3
       chokidar: 5.0.0
       destr: 2.0.5
-      h3: 1.15.10
-      lru-cache: 11.2.7
+      h3: 1.15.11
+      lru-cache: 11.3.5
       node-fetch-native: 1.6.7
       ofetch: 1.5.1
       ufo: 1.6.3
@@ -3894,23 +3919,23 @@ snapshots:
       '@types/unist': 3.0.3
       vfile-message: 4.0.3
 
-  vite@7.3.1(@types/node@24.12.0)(jiti@2.6.1)(lightningcss@1.32.0):
+  vite@7.3.2(@types/node@24.12.2)(jiti@2.6.1)(lightningcss@1.32.0):
     dependencies:
-      esbuild: 0.27.4
+      esbuild: 0.27.7
       fdir: 6.5.0(picomatch@4.0.4)
       picomatch: 4.0.4
-      postcss: 8.5.8
-      rollup: 4.60.0
-      tinyglobby: 0.2.15
+      postcss: 8.5.10
+      rollup: 4.60.2
+      tinyglobby: 0.2.16
     optionalDependencies:
-      '@types/node': 24.12.0
+      '@types/node': 24.12.2
       fsevents: 2.3.3
       jiti: 2.6.1
       lightningcss: 1.32.0
 
-  vitefu@1.1.2(vite@7.3.1(@types/node@24.12.0)(jiti@2.6.1)(lightningcss@1.32.0)):
+  vitefu@1.1.3(vite@7.3.2(@types/node@24.12.2)(jiti@2.6.1)(lightningcss@1.32.0)):
     optionalDependencies:
-      vite: 7.3.1(@types/node@24.12.0)(jiti@2.6.1)(lightningcss@1.32.0)
+      vite: 7.3.2(@types/node@24.12.2)(jiti@2.6.1)(lightningcss@1.32.0)
 
   web-namespaces@2.0.1: {}
 


---

## unknown

---

## unknown

---

## unknown

---

## unknown

---

## unknown

---

## unknown

---

## unknown

---

## 👤 User

Review this dependency-audit diff only. Context: private Astro static site generalsystemsventures; goal is to clear Dependabot advisories for defu, vite, astro, postcss with minimal behavior change. Focus on lockfile correctness, semver risk, build/test/deployment safety, and whether any vulnerable versions remain. Do not modify files. Return sections: Critical, Warnings, Suggestions, Looks Good.
diff --git a/package.json b/package.json
index 6e31a02..1a4123b 100644
--- a/package.json
+++ b/package.json
@@ -13,11 +13,11 @@
     "test": "node --test"
   },
   "dependencies": {
-    "@astrojs/mdx": "^5.0.2",
-    "@astrojs/sitemap": "^3.7.1",
-    "@tailwindcss/vite": "^4.2.2",
-    "astro": "^6.0.8",
-    "tailwindcss": "^4.2.2"
+    "@astrojs/mdx": "^5.0.4",
+    "@astrojs/sitemap": "^3.7.2",
+    "@tailwindcss/vite": "^4.2.4",
+    "astro": "^6.1.9",
+    "tailwindcss": "^4.2.4"
   },
   "packageManager": "pnpm@10.33.0"
 }
diff --git a/pnpm-lock.yaml b/pnpm-lock.yaml
index 07d73be..a66905b 100644
--- a/pnpm-lock.yaml
+++ b/pnpm-lock.yaml
@@ -9,34 +9,34 @@ importers:
   .:
     dependencies:
       '@astrojs/mdx':
-        specifier: ^5.0.2
-        version: 5.0.3(astro@6.1.1(@types/node@24.12.0)(@vercel/functions@3.4.3)(jiti@2.6.1)(lightningcss@1.32.0)(rollup@4.60.0))
+        specifier: ^5.0.4
+        version: 5.0.4(astro@6.1.9(@types/node@24.12.2)(@vercel/functions@3.4.3)(jiti@2.6.1)(lightningcss@1.32.0)(rollup@4.60.2))
       '@astrojs/sitemap':
-        specifier: ^3.7.1
+        specifier: ^3.7.2
         version: 3.7.2
       '@tailwindcss/vite':
-        specifier: ^4.2.2
-        version: 4.2.2(vite@7.3.1(@types/node@24.12.0)(jiti@2.6.1)(lightningcss@1.32.0))
+        specifier: ^4.2.4
+        version: 4.2.4(vite@7.3.2(@types/node@24.12.2)(jiti@2.6.1)(lightningcss@1.32.0))
       astro:
-        specifier: ^6.0.8
-        version: 6.1.1(@types/node@24.12.0)(@vercel/functions@3.4.3)(jiti@2.6.1)(lightningcss@1.32.0)(rollup@4.60.0)
+        specifier: ^6.1.9
+        version: 6.1.9(@types/node@24.12.2)(@vercel/functions@3.4.3)(jiti@2.6.1)(lightningcss@1.32.0)(rollup@4.60.2)
       tailwindcss:
-        specifier: ^4.2.2
-        version: 4.2.2
+        specifier: ^4.2.4
+        version: 4.2.4
 
 packages:
 
   '@astrojs/compiler@3.0.1':
     resolution: {integrity: sha512-z97oYbdebO5aoWzuJ/8q5hLK232+17KcLZ7cJ8BCWk6+qNzVxn/gftC0KzMBUTD8WAaBkPpNSQK6PXLnNrZ0CA==}
 
-  '@astrojs/internal-helpers@0.8.0':
-    resolution: {integrity: sha512-J56GrhEiV+4dmrGLPNOl2pZjpHXAndWVyiVDYGDuw6MWKpBSEMLdFxHzeM/6sqaknw9M+HFfHZAcvi3OfT3D/w==}
+  '@astrojs/internal-helpers@0.9.0':
+    resolution: {integrity: sha512-GdYkzR26re8izmyYlBqf4z2s7zNngmWLFuxw0UKiPNqHraZGS6GKWIwSHgS22RDlu2ePFJ8bzmpBcUszut/SDg==}
 
-  '@astrojs/markdown-remark@7.1.0':
-    resolution: {integrity: sha512-P+HnCsu2js3BoTc8kFmu+E9gOcFeMdPris75g+Zl4sY8+bBRbSQV6xzcBDbZ27eE7yBGEGQoqjpChx+KJYIPYQ==}
+  '@astrojs/markdown-remark@7.1.1':
+    resolution: {integrity: sha512-C6e9BnLGlbdv6bV8MYGeHpHxsUHrCrB4OuRLqi5LI7oiBVcBcqfUN06zpwFQdHgV48QCCrMmLpyqBr7VqC+swA==}
 
-  '@astrojs/mdx@5.0.3':
-    resolution: {integrity: sha512-zv/OlM5sZZvyjHqJjR3FjJvoCgbxdqj3t4jO/gSEUNcck3BjdtMgNQw8UgPfAGe4yySdG4vjZ3OC5wUxhu7ckg==}
+  '@astrojs/mdx@5.0.4':
+    resolution: {integrity: sha512-tSbuuYueNODiFAFaME7pjHY5lOLoxBYJi1cKd6scw9+a4ZO7C7UGdafEoVAQvOV2eO8a6RaHSAJYGVPL1w8BPA==}
     engines: {node: '>=22.12.0'}
     peerDependencies:
       astro: ^6.0.0
@@ -48,8 +48,8 @@ packages:
   '@astrojs/sitemap@3.7.2':
     resolution: {integrity: sha512-PqkzkcZTb5ICiyIR8VoKbIAP/laNRXi5tw616N1Ckk+40oNB8Can1AzVV56lrbC5GKSZFCyJYUVYqVivMisvpA==}
 
-  '@astrojs/telemetry@3.3.0':
-    resolution: {integrity: sha512-UFBgfeldP06qu6khs/yY+q1cDAaArM2/7AEIqQ9Cuvf7B1hNLq0xDrZkct+QoIGyjq56y8IaE2I3CTvG99mlhQ==}
+  '@astrojs/telemetry@3.3.1':
+    resolution: {integrity: sha512-7fcIxXS9J4ls5tr8b3ww9rbAIz2+HrhNJYZdkAhhB4za/I5IZ/60g+Bs8q7zwG0tOIZfNB4JWhVJ1Qkl/OrNCw==}
     engines: {node: 18.20.8 || ^20.3.0 || >=22.0.0}
 
   '@babel/helper-string-parser@7.27.1':
@@ -73,167 +73,167 @@ packages:
     resolution: {integrity: sha512-VERIM64vtTP1C4mxQ5thVT9fK0apjPFobqybMtA1UdUujWka24ERHbRHFGmpbbhp73MhV+KSsHQH9C6uOTdEQA==}
     engines: {node: '>=18'}
 
-  '@clack/core@1.1.0':
-    resolution: {integrity: sha512-SVcm4Dqm2ukn64/8Gub2wnlA5nS2iWJyCkdNHcvNHPIeBTGojpdJ+9cZKwLfmqy7irD4N5qLteSilJlE0WLAtA==}
+  '@clack/core@1.2.0':
+    resolution: {integrity: sha512-qfxof/3T3t9DPU/Rj3OmcFyZInceqj/NVtO9rwIuJqCUgh32gwPjpFQQp/ben07qKlhpwq7GzfWpST4qdJ5Drg==}
 
-  '@clack/prompts@1.1.0':
-    resolution: {integrity: sha512-pkqbPGtohJAvm4Dphs2M8xE29ggupihHdy1x84HNojZuMtFsHiUlRvqD24tM2+XmI+61LlfNceM3Wr7U5QES5g==}
+  '@clack/prompts@1.2.0':
+    resolution: {integrity: sha512-4jmztR9fMqPMjz6H/UZXj0zEmE43ha1euENwkckKKel4XpSfokExPo5AiVStdHSAlHekz4d0CA/r45Ok1E4D3w==}
 
-  '@emnapi/runtime@1.9.1':
-    resolution: {integrity: sha512-VYi5+ZVLhpgK4hQ0TAjiQiZ6ol0oe4mBx7mVv7IflsiEp0OWoVsp/+f9Vc1hOhE0TtkORVrI1GvzyreqpgWtkA==}
+  '@emnapi/runtime@1.10.0':
+    resolution: {integrity: sha512-ewvYlk86xUoGI0zQRNq/mC+16R1QeDlKQy21Ki3oSYXNgLb45GV1P6A0M+/s6nyCuNDqe5VpaY84BzXGwVbwFA==}
 
-  '@esbuild/aix-ppc64@0.27.4':
-    resolution: {integrity: sha512-cQPwL2mp2nSmHHJlCyoXgHGhbEPMrEEU5xhkcy3Hs/O7nGZqEpZ2sUtLaL9MORLtDfRvVl2/3PAuEkYZH0Ty8Q==}
+  '@esbuild/aix-ppc64@0.27.7':
+    resolution: {integrity: sha512-EKX3Qwmhz1eMdEJokhALr0YiD0lhQNwDqkPYyPhiSwKrh7/4KRjQc04sZ8db+5DVVnZ1LmbNDI1uAMPEUBnQPg==}
     engines: {node: '>=18'}
     cpu: [ppc64]
     os: [aix]
 
-  '@esbuild/android-arm64@0.27.4':
-    resolution: {integrity: sha512-gdLscB7v75wRfu7QSm/zg6Rx29VLdy9eTr2t44sfTW7CxwAtQghZ4ZnqHk3/ogz7xao0QAgrkradbBzcqFPasw==}
+  '@esbuild/android-arm64@0.27.7':
+    resolution: {integrity: sha512-62dPZHpIXzvChfvfLJow3q5dDtiNMkwiRzPylSCfriLvZeq0a1bWChrGx/BbUbPwOrsWKMn8idSllklzBy+dgQ==}
     engines: {node: '>=18'}
     cpu: [arm64]
     os: [android]
 
-  '@esbuild/android-arm@0.27.4':
-    resolution: {integrity: sha512-X9bUgvxiC8CHAGKYufLIHGXPJWnr0OCdR0anD2e21vdvgCI8lIfqFbnoeOz7lBjdrAGUhqLZLcQo6MLhTO2DKQ==}
+  '@esbuild/android-arm@0.27.7':
+    resolution: {integrity: sha512-jbPXvB4Yj2yBV7HUfE2KHe4GJX51QplCN1pGbYjvsyCZbQmies29EoJbkEc+vYuU5o45AfQn37vZlyXy4YJ8RQ==}
     engines: {node: '>=18'}
     cpu: [arm]
     os: [android]
 
-  '@esbuild/android-x64@0.27.4':
-    resolution: {integrity: sha512-PzPFnBNVF292sfpfhiyiXCGSn9HZg5BcAz+ivBuSsl6Rk4ga1oEXAamhOXRFyMcjwr2DVtm40G65N3GLeH1Lvw==}
+  '@esbuild/android-x64@0.27.7':
+    resolution: {integrity: sha512-x5VpMODneVDb70PYV2VQOmIUUiBtY3D3mPBG8NxVk5CogneYhkR7MmM3yR/uMdITLrC1ml/NV1rj4bMJuy9MCg==}
     engines: {node: '>=18'}
     cpu: [x64]
     os: [android]
 
-  '@esbuild/darwin-arm64@0.27.4':
-    resolution: {integrity: sha512-b7xaGIwdJlht8ZFCvMkpDN6uiSmnxxK56N2GDTMYPr2/gzvfdQN8rTfBsvVKmIVY/X7EM+/hJKEIbbHs9oA4tQ==}
+  '@esbuild/darwin-arm64@0.27.7':
+    resolution: {integrity: sha512-5lckdqeuBPlKUwvoCXIgI2D9/ABmPq3Rdp7IfL70393YgaASt7tbju3Ac+ePVi3KDH6N2RqePfHnXkaDtY9fkw==}
     engines: {node: '>=18'}
     cpu: [arm64]
     os: [darwin]
 
-  '@esbuild/darwin-x64@0.27.4':
-    resolution: {integrity: sha512-sR+OiKLwd15nmCdqpXMnuJ9W2kpy0KigzqScqHI3Hqwr7IXxBp3Yva+yJwoqh7rE8V77tdoheRYataNKL4QrPw==}
+  '@esbuild/darwin-x64@0.27.7':
+    resolution: {integrity: sha512-rYnXrKcXuT7Z+WL5K980jVFdvVKhCHhUwid+dDYQpH+qu+TefcomiMAJpIiC2EM3Rjtq0sO3StMV/+3w3MyyqQ==}
     engines: {node: '>=18'}
     cpu: [x64]
     os: [darwin]
 
-  '@esbuild/freebsd-arm64@0.27.4':
-    resolution: {integrity: sha512-jnfpKe+p79tCnm4GVav68A7tUFeKQwQyLgESwEAUzyxk/TJr4QdGog9sqWNcUbr/bZt/O/HXouspuQDd9JxFSw==}
+  '@esbuild/freebsd-arm64@0.27.7':
+    resolution: {integrity: sha512-B48PqeCsEgOtzME2GbNM2roU29AMTuOIN91dsMO30t+Ydis3z/3Ngoj5hhnsOSSwNzS+6JppqWsuhTp6E82l2w==}
     engines: {node: '>=18'}
     cpu: [arm64]
     os: [freebsd]
 
-  '@esbuild/freebsd-x64@0.27.4':
-    resolution: {integrity: sha512-2kb4ceA/CpfUrIcTUl1wrP/9ad9Atrp5J94Lq69w7UwOMolPIGrfLSvAKJp0RTvkPPyn6CIWrNy13kyLikZRZQ==}
+  '@esbuild/freebsd-x64@0.27.7':
+    resolution: {integrity: sha512-jOBDK5XEjA4m5IJK3bpAQF9/Lelu/Z9ZcdhTRLf4cajlB+8VEhFFRjWgfy3M1O4rO2GQ/b2dLwCUGpiF/eATNQ==}
     engines: {node: '>=18'}
     cpu: [x64]
     os: [freebsd]
 
-  '@esbuild/linux-arm64@0.27.4':
-    resolution: {integrity: sha512-7nQOttdzVGth1iz57kxg9uCz57dxQLHWxopL6mYuYthohPKEK0vU0C3O21CcBK6KDlkYVcnDXY099HcCDXd9dA==}
+  '@esbuild/linux-arm64@0.27.7':
+    resolution: {integrity: sha512-RZPHBoxXuNnPQO9rvjh5jdkRmVizktkT7TCDkDmQ0W2SwHInKCAV95GRuvdSvA7w4VMwfCjUiPwDi0ZO6Nfe9A==}
     engines: {node: '>=18'}
     cpu: [arm64]
     os: [linux]
 
-  '@esbuild/linux-arm@0.27.4':
-    resolution: {integrity: sha512-aBYgcIxX/wd5n2ys0yESGeYMGF+pv6g0DhZr3G1ZG4jMfruU9Tl1i2Z+Wnj9/KjGz1lTLCcorqE2viePZqj4Eg==}
+  '@esbuild/linux-arm@0.27.7':
+    resolution: {integrity: sha512-RkT/YXYBTSULo3+af8Ib0ykH8u2MBh57o7q/DAs3lTJlyVQkgQvlrPTnjIzzRPQyavxtPtfg0EopvDyIt0j1rA==}
     engines: {node: '>=18'}
     cpu: [arm]
     os: [linux]
 
-  '@esbuild/linux-ia32@0.27.4':
-    resolution: {integrity: sha512-oPtixtAIzgvzYcKBQM/qZ3R+9TEUd1aNJQu0HhGyqtx6oS7qTpvjheIWBbes4+qu1bNlo2V4cbkISr8q6gRBFA==}
+  '@esbuild/linux-ia32@0.27.7':
+    resolution: {integrity: sha512-GA48aKNkyQDbd3KtkplYWT102C5sn/EZTY4XROkxONgruHPU72l+gW+FfF8tf2cFjeHaRbWpOYa/uRBz/Xq1Pg==}
     engines: {node: '>=18'}
     cpu: [ia32]
     os: [linux]
 
-  '@esbuild/linux-loong64@0.27.4':
-    resolution: {integrity: sha512-8mL/vh8qeCoRcFH2nM8wm5uJP+ZcVYGGayMavi8GmRJjuI3g1v6Z7Ni0JJKAJW+m0EtUuARb6Lmp4hMjzCBWzA==}
+  '@esbuild/linux-loong64@0.27.7':
+    resolution: {integrity: sha512-a4POruNM2oWsD4WKvBSEKGIiWQF8fZOAsycHOt6JBpZ+JN2n2JH9WAv56SOyu9X5IqAjqSIPTaJkqN8F7XOQ5Q==}
     engines: {node: '>=18'}
     cpu: [loong64]
     os: [linux]
 
-  '@esbuild/linux-mips64el@0.27.4':
-    resolution: {integrity: sha512-1RdrWFFiiLIW7LQq9Q2NES+HiD4NyT8Itj9AUeCl0IVCA459WnPhREKgwrpaIfTOe+/2rdntisegiPWn/r/aAw==}
+  '@esbuild/linux-mips64el@0.27.7':
+    resolution: {integrity: sha512-KabT5I6StirGfIz0FMgl1I+R1H73Gp0ofL9A3nG3i/cYFJzKHhouBV5VWK1CSgKvVaG4q1RNpCTR2LuTVB3fIw==}
     engines: {node: '>=18'}
     cpu: [mips64el]
     os: [linux]
 
-  '@esbuild/linux-ppc64@0.27.4':
-    resolution: {integrity: sha512-tLCwNG47l3sd9lpfyx9LAGEGItCUeRCWeAx6x2Jmbav65nAwoPXfewtAdtbtit/pJFLUWOhpv0FpS6GQAmPrHA==}
+  '@esbuild/linux-ppc64@0.27.7':
+    resolution: {integrity: sha512-gRsL4x6wsGHGRqhtI+ifpN/vpOFTQtnbsupUF5R5YTAg+y/lKelYR1hXbnBdzDjGbMYjVJLJTd2OFmMewAgwlQ==}
     engines: {node: '>=18'}
     cpu: [ppc64]
     os: [linux]
 
-  '@esbuild/linux-riscv64@0.27.4':
-    resolution: {integrity: sha512-BnASypppbUWyqjd1KIpU4AUBiIhVr6YlHx/cnPgqEkNoVOhHg+YiSVxM1RLfiy4t9cAulbRGTNCKOcqHrEQLIw==}
+  '@esbuild/linux-riscv64@0.27.7':
+    resolution: {integrity: sha512-hL25LbxO1QOngGzu2U5xeXtxXcW+/GvMN3ejANqXkxZ/opySAZMrc+9LY/WyjAan41unrR3YrmtTsUpwT66InQ==}
     engines: {node: '>=18'}
     cpu: [riscv64]
     os: [linux]
 
-  '@esbuild/linux-s390x@0.27.4':
-    resolution: {integrity: sha512-+eUqgb/Z7vxVLezG8bVB9SfBie89gMueS+I0xYh2tJdw3vqA/0ImZJ2ROeWwVJN59ihBeZ7Tu92dF/5dy5FttA==}
+  '@esbuild/linux-s390x@0.27.7':
+    resolution: {integrity: sha512-2k8go8Ycu1Kb46vEelhu1vqEP+UeRVj2zY1pSuPdgvbd5ykAw82Lrro28vXUrRmzEsUV0NzCf54yARIK8r0fdw==}
     engines: {node: '>=18'}
     cpu: [s390x]
     os: [linux]
 
-  '@esbuild/linux-x64@0.27.4':
-    resolution: {integrity: sha512-S5qOXrKV8BQEzJPVxAwnryi2+Iq5pB40gTEIT69BQONqR7JH1EPIcQ/Uiv9mCnn05jff9umq/5nqzxlqTOg9NA==}
+  '@esbuild/linux-x64@0.27.7':
+    resolution: {integrity: sha512-hzznmADPt+OmsYzw1EE33ccA+HPdIqiCRq7cQeL1Jlq2gb1+OyWBkMCrYGBJ+sxVzve2ZJEVeePbLM2iEIZSxA==}
     engines: {node: '>=18'}
     cpu: [x64]
     os: [linux]
 
-  '@esbuild/netbsd-arm64@0.27.4':
-    resolution: {integrity: sha512-xHT8X4sb0GS8qTqiwzHqpY00C95DPAq7nAwX35Ie/s+LO9830hrMd3oX0ZMKLvy7vsonee73x0lmcdOVXFzd6Q==}
+  '@esbuild/netbsd-arm64@0.27.7':
+    resolution: {integrity: sha512-b6pqtrQdigZBwZxAn1UpazEisvwaIDvdbMbmrly7cDTMFnw/+3lVxxCTGOrkPVnsYIosJJXAsILG9XcQS+Yu6w==}
     engines: {node: '>=18'}
     cpu: [arm64]
     os: [netbsd]
 
-  '@esbuild/netbsd-x64@0.27.4':
-    resolution: {integrity: sha512-RugOvOdXfdyi5Tyv40kgQnI0byv66BFgAqjdgtAKqHoZTbTF2QqfQrFwa7cHEORJf6X2ht+l9ABLMP0dnKYsgg==}
+  '@esbuild/netbsd-x64@0.27.7':
+    resolution: {integrity: sha512-OfatkLojr6U+WN5EDYuoQhtM+1xco+/6FSzJJnuWiUw5eVcicbyK3dq5EeV/QHT1uy6GoDhGbFpprUiHUYggrw==}
     engines: {node: '>=18'}
     cpu: [x64]
     os: [netbsd]
 
-  '@esbuild/openbsd-arm64@0.27.4':
-    resolution: {integrity: sha512-2MyL3IAaTX+1/qP0O1SwskwcwCoOI4kV2IBX1xYnDDqthmq5ArrW94qSIKCAuRraMgPOmG0RDTA74mzYNQA9ow==}
+  '@esbuild/openbsd-arm64@0.27.7':
+    resolution: {integrity: sha512-AFuojMQTxAz75Fo8idVcqoQWEHIXFRbOc1TrVcFSgCZtQfSdc1RXgB3tjOn/krRHENUB4j00bfGjyl2mJrU37A==}
     engines: {node: '>=18'}
     cpu: [arm64]
     os: [openbsd]
 
-  '@esbuild/openbsd-x64@0.27.4':
-    resolution: {integrity: sha512-u8fg/jQ5aQDfsnIV6+KwLOf1CmJnfu1ShpwqdwC0uA7ZPwFws55Ngc12vBdeUdnuWoQYx/SOQLGDcdlfXhYmXQ==}
+  '@esbuild/openbsd-x64@0.27.7':
+    resolution: {integrity: sha512-+A1NJmfM8WNDv5CLVQYJ5PshuRm/4cI6WMZRg1by1GwPIQPCTs1GLEUHwiiQGT5zDdyLiRM/l1G0Pv54gvtKIg==}
     engines: {node: '>=18'}
     cpu: [x64]
     os: [openbsd]
 
-  '@esbuild/openharmony-arm64@0.27.4':
-    resolution: {integrity: sha512-JkTZrl6VbyO8lDQO3yv26nNr2RM2yZzNrNHEsj9bm6dOwwu9OYN28CjzZkH57bh4w0I2F7IodpQvUAEd1mbWXg==}
+  '@esbuild/openharmony-arm64@0.27.7':
+    resolution: {integrity: sha512-+KrvYb/C8zA9CU/g0sR6w2RBw7IGc5J2BPnc3dYc5VJxHCSF1yNMxTV5LQ7GuKteQXZtspjFbiuW5/dOj7H4Yw==}
     engines: {node: '>=18'}
     cpu: [arm64]
     os: [openharmony]
 
-  '@esbuild/sunos-x64@0.27.4':
-    resolution: {integrity: sha512-/gOzgaewZJfeJTlsWhvUEmUG4tWEY2Spp5M20INYRg2ZKl9QPO3QEEgPeRtLjEWSW8FilRNacPOg8R1uaYkA6g==}
+  '@esbuild/sunos-x64@0.27.7':
+    resolution: {integrity: sha512-ikktIhFBzQNt/QDyOL580ti9+5mL/YZeUPKU2ivGtGjdTYoqz6jObj6nOMfhASpS4GU4Q/Clh1QtxWAvcYKamA==}
     engines: {node: '>=18'}
     cpu: [x64]
     os: [sunos]
 
-  '@esbuild/win32-arm64@0.27.4':
-    resolution: {integrity: sha512-Z9SExBg2y32smoDQdf1HRwHRt6vAHLXcxD2uGgO/v2jK7Y718Ix4ndsbNMU/+1Qiem9OiOdaqitioZwxivhXYg==}
+  '@esbuild/win32-arm64@0.27.7':
+    resolution: {integrity: sha512-7yRhbHvPqSpRUV7Q20VuDwbjW5kIMwTHpptuUzV+AA46kiPze5Z7qgt6CLCK3pWFrHeNfDd1VKgyP4O+ng17CA==}
     engines: {node: '>=18'}
     cpu: [arm64]
     os: [win32]
 
-  '@esbuild/win32-ia32@0.27.4':
-    resolution: {integrity: sha512-DAyGLS0Jz5G5iixEbMHi5KdiApqHBWMGzTtMiJ72ZOLhbu/bzxgAe8Ue8CTS3n3HbIUHQz/L51yMdGMeoxXNJw==}
+  '@esbuild/win32-ia32@0.27.7':
+    resolution: {integrity: sha512-SmwKXe6VHIyZYbBLJrhOoCJRB/Z1tckzmgTLfFYOfpMAx63BJEaL9ExI8x7v0oAO3Zh6D/Oi1gVxEYr5oUCFhw==}
     engines: {node: '>=18'}
     cpu: [ia32]
     os: [win32]
 
-  '@esbuild/win32-x64@0.27.4':
-    resolution: {integrity: sha512-+knoa0BDoeXgkNvvV1vvbZX4+hizelrkwmGJBdT17t8FNPwG2lKemmuMZlmaNQ3ws3DKKCxpb4zRZEIp3UxFCg==}
+  '@esbuild/win32-x64@0.27.7':
+    resolution: {integrity: sha512-56hiAJPhwQ1R4i+21FVF7V8kSD5zZTdHcVuRFMW0hn753vVfQN8xlx4uOPT4xoGH0Z/oVATuR82AiqSTDIpaHg==}
     engines: {node: '>=18'}
     cpu: [x64]
     os: [win32]
@@ -422,141 +422,141 @@ packages:
       rollup:
         optional: true
 
-  '@rollup/rollup-android-arm-eabi@4.60.0':
-    resolution: {integrity: sha512-WOhNW9K8bR3kf4zLxbfg6Pxu2ybOUbB2AjMDHSQx86LIF4rH4Ft7vmMwNt0loO0eonglSNy4cpD3MKXXKQu0/A==}
+  '@rollup/rollup-android-arm-eabi@4.60.2':
+    resolution: {integrity: sha512-dnlp69efPPg6Uaw2dVqzWRfAWRnYVb1XJ8CyyhIbZeaq4CA5/mLeZ1IEt9QqQxmbdvagjLIm2ZL8BxXv5lH4Yw==}
     cpu: [arm]
     os: [android]
 
-  '@rollup/rollup-android-arm64@4.60.0':
-    resolution: {integrity: sha512-u6JHLll5QKRvjciE78bQXDmqRqNs5M/3GVqZeMwvmjaNODJih/WIrJlFVEihvV0MiYFmd+ZyPr9wxOVbPAG2Iw==}
+  '@rollup/rollup-android-arm64@4.60.2':
+    resolution: {integrity: sha512-OqZTwDRDchGRHHm/hwLOL7uVPB9aUvI0am/eQuWMNyFHf5PSEQmyEeYYheA0EPPKUO/l0uigCp+iaTjoLjVoHg==}
     cpu: [arm64]
     os: [android]
 
-  '@rollup/rollup-darwin-arm64@4.60.0':
-    resolution: {integrity: sha512-qEF7CsKKzSRc20Ciu2Zw1wRrBz4g56F7r/vRwY430UPp/nt1x21Q/fpJ9N5l47WWvJlkNCPJz3QRVw008fi7yA==}
+  '@rollup/rollup-darwin-arm64@4.60.2':
+    resolution: {integrity: sha512-UwRE7CGpvSVEQS8gUMBe1uADWjNnVgP3Iusyda1nSRwNDCsRjnGc7w6El6WLQsXmZTbLZx9cecegumcitNfpmA==}
     cpu: [arm64]
     os: [darwin]
 
-  '@rollup/rollup-darwin-x64@4.60.0':
-    resolution: {integrity: sha512-WADYozJ4QCnXCH4wPB+3FuGmDPoFseVCUrANmA5LWwGmC6FL14BWC7pcq+FstOZv3baGX65tZ378uT6WG8ynTw==}
+  '@rollup/rollup-darwin-x64@4.60.2':
+    resolution: {integrity: sha512-gjEtURKLCC5VXm1I+2i1u9OhxFsKAQJKTVB8WvDAHF+oZlq0GTVFOlTlO1q3AlCTE/DF32c16ESvfgqR7343/g==}
     cpu: [x64]
     os: [darwin]
 
-  '@rollup/rollup-freebsd-arm64@4.60.0':
-    resolution: {integrity: sha512-6b8wGHJlDrGeSE3aH5mGNHBjA0TTkxdoNHik5EkvPHCt351XnigA4pS7Wsj/Eo9Y8RBU6f35cjN9SYmCFBtzxw==}
+  '@rollup/rollup-freebsd-arm64@4.60.2':
+    resolution: {integrity: sha512-Bcl6CYDeAgE70cqZaMojOi/eK63h5Me97ZqAQoh77VPjMysA/4ORQBRGo3rRy45x4MzVlU9uZxs8Uwy7ZaKnBw==}
     cpu: [arm64]
     os: [freebsd]
 
-  '@rollup/rollup-freebsd-x64@4.60.0':
-    resolution: {integrity: sha512-h25Ga0t4jaylMB8M/JKAyrvvfxGRjnPQIR8lnCayyzEjEOx2EJIlIiMbhpWxDRKGKF8jbNH01NnN663dH638mA==}
+  '@rollup/rollup-freebsd-x64@4.60.2':
+    resolution: {integrity: sha512-LU+TPda3mAE2QB0/Hp5VyeKJivpC6+tlOXd1VMoXV/YFMvk/MNk5iXeBfB4MQGRWyOYVJ01625vjkr0Az98OJQ==}
     cpu: [x64]
     os: [freebsd]
 
-  '@rollup/rollup-linux-arm-gnueabihf@4.60.0':
-    resolution: {integrity: sha512-RzeBwv0B3qtVBWtcuABtSuCzToo2IEAIQrcyB/b2zMvBWVbjo8bZDjACUpnaafaxhTw2W+imQbP2BD1usasK4g==}
+  '@rollup/rollup-linux-arm-gnueabihf@4.60.2':
+    resolution: {integrity: sha512-2QxQrM+KQ7DAW4o22j+XZ6RKdxjLD7BOWTP0Bv0tmjdyhXSsr2Ul1oJDQqh9Zf5qOwTuTc7Ek83mOFaKnodPjg==}
     cpu: [arm]
     os: [linux]
     libc: [glibc]
 
-  '@rollup/rollup-linux-arm-musleabihf@4.60.0':
-    resolution: {integrity: sha512-Sf7zusNI2CIU1HLzuu9Tc5YGAHEZs5Lu7N1ssJG4Tkw6e0MEsN7NdjUDDfGNHy2IU+ENyWT+L2obgWiguWibWQ==}
+  '@rollup/rollup-linux-arm-musleabihf@4.60.2':
+    resolution: {integrity: sha512-TbziEu2DVsTEOPif2mKWkMeDMLoYjx95oESa9fkQQK7r/Orta0gnkcDpzwufEcAO2BLBsD7mZkXGFqEdMRRwfw==}
     cpu: [arm]
     os: [linux]
     libc: [musl]
 
-  '@rollup/rollup-linux-arm64-gnu@4.60.0':
-    resolution: {integrity: sha512-DX2x7CMcrJzsE91q7/O02IJQ5/aLkVtYFryqCjduJhUfGKG6yJV8hxaw8pZa93lLEpPTP/ohdN4wFz7yp/ry9A==}
+  '@rollup/rollup-linux-arm64-gnu@4.60.2':
+    resolution: {integrity: sha512-bO/rVDiDUuM2YfuCUwZ1t1cP+/yqjqz+Xf2VtkdppefuOFS2OSeAfgafaHNkFn0t02hEyXngZkxtGqXcXwO8Rg==}
     cpu: [arm64]
     os: [linux]
     libc: [glibc]
 
-  '@rollup/rollup-linux-arm64-musl@4.60.0':
-    resolution: {integrity: sha512-09EL+yFVbJZlhcQfShpswwRZ0Rg+z/CsSELFCnPt3iK+iqwGsI4zht3secj5vLEs957QvFFXnzAT0FFPIxSrkQ==}
+  '@rollup/rollup-linux-arm64-musl@4.60.2':
+    resolution: {integrity: sha512-hr26p7e93Rl0Za+JwW7EAnwAvKkehh12BU1Llm9Ykiibg4uIr2rbpxG9WCf56GuvidlTG9KiiQT/TXT1yAWxTA==}
     cpu: [arm64]
     os: [linux]
     libc: [musl]
 
-  '@rollup/rollup-linux-loong64-gnu@4.60.0':
-    resolution: {integrity: sha512-i9IcCMPr3EXm8EQg5jnja0Zyc1iFxJjZWlb4wr7U2Wx/GrddOuEafxRdMPRYVaXjgbhvqalp6np07hN1w9kAKw==}
+  '@rollup/rollup-linux-loong64-gnu@4.60.2':
+    resolution: {integrity: sha512-pOjB/uSIyDt+ow3k/RcLvUAOGpysT2phDn7TTUB3n75SlIgZzM6NKAqlErPhoFU+npgY3/n+2HYIQVbF70P9/A==}
     cpu: [loong64]
     os: [linux]
     libc: [glibc]
 
-  '@rollup/rollup-linux-loong64-musl@4.60.0':
-    resolution: {integrity: sha512-DGzdJK9kyJ+B78MCkWeGnpXJ91tK/iKA6HwHxF4TAlPIY7GXEvMe8hBFRgdrR9Ly4qebR/7gfUs9y2IoaVEyog==}
+  '@rollup/rollup-linux-loong64-musl@4.60.2':
+    resolution: {integrity: sha512-2/w+q8jszv9Ww1c+6uJT3OwqhdmGP2/4T17cu8WuwyUuuaCDDJ2ojdyYwZzCxx0GcsZBhzi3HmH+J5pZNXnd+Q==}
     cpu: [loong64]
     os: [linux]
     libc: [musl]
 
-  '@rollup/rollup-linux-ppc64-gnu@4.60.0':
-    resolution: {integrity: sha512-RwpnLsqC8qbS8z1H1AxBA1H6qknR4YpPR9w2XX0vo2Sz10miu57PkNcnHVaZkbqyw/kUWfKMI73jhmfi9BRMUQ==}
+  '@rollup/rollup-linux-ppc64-gnu@4.60.2':
+    resolution: {integrity: sha512-11+aL5vKheYgczxtPVVRhdptAM2H7fcDR5Gw4/bTcteuZBlH4oP9f5s9zYO9aGZvoGeBpqXI/9TZZihZ609wKw==}
     cpu: [ppc64]
     os: [linux]
     libc: [glibc]
 
-  '@rollup/rollup-linux-ppc64-musl@4.60.0':
-    resolution: {integrity: sha512-Z8pPf54Ly3aqtdWC3G4rFigZgNvd+qJlOE52fmko3KST9SoGfAdSRCwyoyG05q1HrrAblLbk1/PSIV+80/pxLg==}
+  '@rollup/rollup-linux-ppc64-musl@4.60.2':
+    resolution: {integrity: sha512-i16fokAGK46IVZuV8LIIwMdtqhin9hfYkCh8pf8iC3QU3LpwL+1FSFGej+O7l3E/AoknL6Dclh2oTdnRMpTzFQ==}
     cpu: [ppc64]
     os: [linux]
     libc: [musl]
 
-  '@rollup/rollup-linux-riscv64-gnu@4.60.0':
-    resolution: {integrity: sha512-3a3qQustp3COCGvnP4SvrMHnPQ9d1vzCakQVRTliaz8cIp/wULGjiGpbcqrkv0WrHTEp8bQD/B3HBjzujVWLOA==}
+  '@rollup/rollup-linux-riscv64-gnu@4.60.2':
+    resolution: {integrity: sha512-49FkKS6RGQoriDSK/6E2GkAsAuU5kETFCh7pG4yD/ylj9rKhTmO3elsnmBvRD4PgJPds5W2PkhC82aVwmUcJ7A==}
     cpu: [riscv64]
     os: [linux]
     libc: [glibc]
 
-  '@rollup/rollup-linux-riscv64-musl@4.60.0':
-    resolution: {integrity: sha512-pjZDsVH/1VsghMJ2/kAaxt6dL0psT6ZexQVrijczOf+PeP2BUqTHYejk3l6TlPRydggINOeNRhvpLa0AYpCWSQ==}
+  '@rollup/rollup-linux-riscv64-musl@4.60.2':
+    resolution: {integrity: sha512-mjYNkHPfGpUR00DuM1ZZIgs64Hpf4bWcz9Z41+4Q+pgDx73UwWdAYyf6EG/lRFldmdHHzgrYyge5akFUW0D3mQ==}
     cpu: [riscv64]
     os: [linux]
     libc: [musl]
 
-  '@rollup/rollup-linux-s390x-gnu@4.60.0':
-    resolution: {integrity: sha512-3ObQs0BhvPgiUVZrN7gqCSvmFuMWvWvsjG5ayJ3Lraqv+2KhOsp+pUbigqbeWqueGIsnn+09HBw27rJ+gYK4VQ==}
+  '@rollup/rollup-linux-s390x-gnu@4.60.2':
+    resolution: {integrity: sha512-ALyvJz965BQk8E9Al/JDKKDLH2kfKFLTGMlgkAbbYtZuJt9LU8DW3ZoDMCtQpXAltZxwBHevXz5u+gf0yA0YoA==}
     cpu: [s390x]
     os: [linux]
     libc: [glibc]
 
-  '@rollup/rollup-linux-x64-gnu@4.60.0':
-    resolution: {integrity: sha512-EtylprDtQPdS5rXvAayrNDYoJhIz1/vzN2fEubo3yLE7tfAw+948dO0g4M0vkTVFhKojnF+n6C8bDNe+gDRdTg==}
+  '@rollup/rollup-linux-x64-gnu@4.60.2':
+    resolution: {integrity: sha512-UQjrkIdWrKI626Du8lCQ6MJp/6V1LAo2bOK9OTu4mSn8GGXIkPXk/Vsp4bLHCd9Z9Iz2OTEaokUE90VweJgIYQ==}
     cpu: [x64]
     os: [linux]
     libc: [glibc]
 
-  '@rollup/rollup-linux-x64-musl@4.60.0':
-    resolution: {integrity: sha512-k09oiRCi/bHU9UVFqD17r3eJR9bn03TyKraCrlz5ULFJGdJGi7VOmm9jl44vOJvRJ6P7WuBi/s2A97LxxHGIdw==}
+  '@rollup/rollup-linux-x64-musl@4.60.2':
+    resolution: {integrity: sha512-bTsRGj6VlSdn/XD4CGyzMnzaBs9bsRxy79eTqTCBsA8TMIEky7qg48aPkvJvFe1HyzQ5oMZdg7AnVlWQSKLTnw==}
     cpu: [x64]
     os: [linux]
     libc: [musl]
 
-  '@rollup/rollup-openbsd-x64@4.60.0':
-    resolution: {integrity: sha512-1o/0/pIhozoSaDJoDcec+IVLbnRtQmHwPV730+AOD29lHEEo4F5BEUB24H0OBdhbBBDwIOSuf7vgg0Ywxdfiiw==}
+  '@rollup/rollup-openbsd-x64@4.60.2':
+    resolution: {integrity: sha512-6d4Z3534xitaA1FcMWP7mQPq5zGwBmGbhphh2DwaA1aNIXUu3KTOfwrWpbwI4/Gr0uANo7NTtaykFyO2hPuFLg==}
     cpu: [x64]
     os: [openbsd]
 
-  '@rollup/rollup-openharmony-arm64@4.60.0':
-    resolution: {integrity: sha512-pESDkos/PDzYwtyzB5p/UoNU/8fJo68vcXM9ZW2V0kjYayj1KaaUfi1NmTUTUpMn4UhU4gTuK8gIaFO4UGuMbA==}
+  '@rollup/rollup-openharmony-arm64@4.60.2':
+    resolution: {integrity: sha512-NetAg5iO2uN7eB8zE5qrZ3CSil+7IJt4WDFLcC75Ymywq1VZVD6qJ6EvNLjZ3rEm6gB7XW5JdT60c6MN35Z85Q==}
     cpu: [arm64]
     os: [openharmony]
 
-  '@rollup/rollup-win32-arm64-msvc@4.60.0':
-    resolution: {integrity: sha512-hj1wFStD7B1YBeYmvY+lWXZ7ey73YGPcViMShYikqKT1GtstIKQAtfUI6yrzPjAy/O7pO0VLXGmUVWXQMaYgTQ==}
+  '@rollup/rollup-win32-arm64-msvc@4.60.2':
+    resolution: {integrity: sha512-NCYhOotpgWZ5kdxCZsv6Iudx0wX8980Q/oW4pNFNihpBKsDbEA1zpkfxJGC0yugsUuyDZ7gL37dbzwhR0VI7pQ==}
     cpu: [arm64]
     os: [win32]
 
-  '@rollup/rollup-win32-ia32-msvc@4.60.0':
-    resolution: {integrity: sha512-SyaIPFoxmUPlNDq5EHkTbiKzmSEmq/gOYFI/3HHJ8iS/v1mbugVa7dXUzcJGQfoytp9DJFLhHH4U3/eTy2Bq4w==}
+  '@rollup/rollup-win32-ia32-msvc@4.60.2':
+    resolution: {integrity: sha512-RXsaOqXxfoUBQoOgvmmijVxJnW2IGB0eoMO7F8FAjaj0UTywUO/luSqimWBJn04WNgUkeNhh7fs7pESXajWmkg==}
     cpu: [ia32]
     os: [win32]
 
-  '@rollup/rollup-win32-x64-gnu@4.60.0':
-    resolution: {integrity: sha512-RdcryEfzZr+lAr5kRm2ucN9aVlCCa2QNq4hXelZxb8GG0NJSazq44Z3PCCc8wISRuCVnGs0lQJVX5Vp6fKA+IA==}
+  '@rollup/rollup-win32-x64-gnu@4.60.2':
+    resolution: {integrity: sha512-qdAzEULD+/hzObedtmV6iBpdL5TIbKVztGiK7O3/KYSf+HIzU257+MX1EXJcyIiDbMAqmbwaufcYPvyRryeZtA==}
     cpu: [x64]
     os: [win32]
 
-  '@rollup/rollup-win32-x64-msvc@4.60.0':
-    resolution: {integrity: sha512-PrsWNQ8BuE00O3Xsx3ALh2Df8fAj9+cvvX9AIA6o4KpATR98c9mud4XtDWVvsEuyia5U4tVSTKygawyJkjm60w==}
+  '@rollup/rollup-win32-x64-msvc@4.60.2':
+    resolution: {integrity: sha512-Nd/SgG27WoA9e+/TdK74KnHz852TLa94ovOYySo/yMPuTmpckK/jIF2jSwS3g7ELSKXK13/cVdmg1Z/DaCWKxA==}
     cpu: [x64]
     os: [win32]
 
@@ -591,69 +591,69 @@ packages:
   '@shikijs/vscode-textmate@10.0.2':
     resolution: {integrity: sha512-83yeghZ2xxin3Nj8z1NMd/NCuca+gsYXswywDy5bHvwlWL8tpTQmzGeUuHd9FC3E/SBEMvzJRwWEOz5gGes9Qg==}
 
-  '@tailwindcss/node@4.2.2':
-    resolution: {integrity: sha512-pXS+wJ2gZpVXqFaUEjojq7jzMpTGf8rU6ipJz5ovJV6PUGmlJ+jvIwGrzdHdQ80Sg+wmQxUFuoW1UAAwHNEdFA==}
+  '@tailwindcss/node@4.2.4':
+    resolution: {integrity: sha512-Ai7+yQPxz3ddrDQzFfBKdHEVBg0w3Zl83jnjuwxnZOsnH9pGn93QHQtpU0p/8rYWxvbFZHneni6p1BSLK4DkGA==}
 
-  '@tailwindcss/oxide-android-arm64@4.2.2':
-    resolution: {integrity: sha512-dXGR1n+P3B6748jZO/SvHZq7qBOqqzQ+yFrXpoOWWALWndF9MoSKAT3Q0fYgAzYzGhxNYOoysRvYlpixRBBoDg==}
+  '@tailwindcss/oxide-android-arm64@4.2.4':
+    resolution: {integrity: sha512-e7MOr1SAn9U8KlZzPi1ZXGZHeC5anY36qjNwmZv9pOJ8E4Q6jmD1vyEHkQFmNOIN7twGPEMXRHmitN4zCMN03g==}
     engines: {node: '>= 20'}
     cpu: [arm64]
     os: [android]
 
-  '@tailwindcss/oxide-darwin-arm64@4.2.2':
-    resolution: {integrity: sha512-iq9Qjr6knfMpZHj55/37ouZeykwbDqF21gPFtfnhCCKGDcPI/21FKC9XdMO/XyBM7qKORx6UIhGgg6jLl7BZlg==}
+  '@tailwindcss/oxide-darwin-arm64@4.2.4':
+    resolution: {integrity: sha512-tSC/Kbqpz/5/o/C2sG7QvOxAKqyd10bq+ypZNf+9Fi2TvbVbv1zNpcEptcsU7DPROaSbVgUXmrzKhurFvo5eDg==}
     engines: {node: '>= 20'}
     cpu: [arm64]
     os: [darwin]
 
-  '@tailwindcss/oxide-darwin-x64@4.2.2':
-    resolution: {integrity: sha512-BlR+2c3nzc8f2G639LpL89YY4bdcIdUmiOOkv2GQv4/4M0vJlpXEa0JXNHhCHU7VWOKWT/CjqHdTP8aUuDJkuw==}
+  '@tailwindcss/oxide-darwin-x64@4.2.4':
+    resolution: {integrity: sha512-yPyUXn3yO/ufR6+Kzv0t4fCg2qNr90jxXc5QqBpjlPNd0NqyDXcmQb/6weunH/MEDXW5dhyEi+agTDiqa3WsGg==}
     engines: {node: '>= 20'}
     cpu: [x64]
     os: [darwin]
 
-  '@tailwindcss/oxide-freebsd-x64@4.2.2':
-    resolution: {integrity: sha512-YUqUgrGMSu2CDO82hzlQ5qSb5xmx3RUrke/QgnoEx7KvmRJHQuZHZmZTLSuuHwFf0DJPybFMXMYf+WJdxHy/nQ==}
+  '@tailwindcss/oxide-freebsd-x64@4.2.4':
+    resolution: {integrity: sha512-BoMIB4vMQtZsXdGLVc2z+P9DbETkiopogfWZKbWwM8b/1Vinbs4YcUwo+kM/KeLkX3Ygrf4/PsRndKaYhS8Eiw==}
     engines: {node: '>= 20'}
     cpu: [x64]
     os: [freebsd]
 
-  '@tailwindcss/oxide-linux-arm-gnueabihf@4.2.2':
-    resolution: {integrity: sha512-FPdhvsW6g06T9BWT0qTwiVZYE2WIFo2dY5aCSpjG/S/u1tby+wXoslXS0kl3/KXnULlLr1E3NPRRw0g7t2kgaQ==}
+  '@tailwindcss/oxide-linux-arm-gnueabihf@4.2.4':
+    resolution: {integrity: sha512-7pIHBLTHYRAlS7V22JNuTh33yLH4VElwKtB3bwchK/UaKUPpQ0lPQiOWcbm4V3WP2I6fNIJ23vABIvoy2izdwA==}
     engines: {node: '>= 20'}
     cpu: [arm]
     os: [linux]
 
-  '@tailwindcss/oxide-linux-arm64-gnu@4.2.2':
-    resolution: {integrity: sha512-4og1V+ftEPXGttOO7eCmW7VICmzzJWgMx+QXAJRAhjrSjumCwWqMfkDrNu1LXEQzNAwz28NCUpucgQPrR4S2yw==}
+  '@tailwindcss/oxide-linux-arm64-gnu@4.2.4':
+    resolution: {integrity: sha512-+E4wxJ0ZGOzSH325reXTWB48l42i93kQqMvDyz5gqfRzRZ7faNhnmvlV4EPGJU3QJM/3Ab5jhJ5pCRUsKn6OQw==}
     engines: {node: '>= 20'}
     cpu: [arm64]
     os: [linux]
     libc: [glibc]
 
-  '@tailwindcss/oxide-linux-arm64-musl@4.2.2':
-    resolution: {integrity: sha512-oCfG/mS+/+XRlwNjnsNLVwnMWYH7tn/kYPsNPh+JSOMlnt93mYNCKHYzylRhI51X+TbR+ufNhhKKzm6QkqX8ag==}
+  '@tailwindcss/oxide-linux-arm64-musl@4.2.4':
+    resolution: {integrity: sha512-bBADEGAbo4ASnppIziaQJelekCxdMaxisrk+fB7Thit72IBnALp9K6ffA2G4ruj90G9XRS2VQ6q2bCKbfFV82g==}
     engines: {node: '>= 20'}
     cpu: [arm64]
     os: [linux]
     libc: [musl]
 
-  '@tailwindcss/oxide-linux-x64-gnu@4.2.2':
-    resolution: {integrity: sha512-rTAGAkDgqbXHNp/xW0iugLVmX62wOp2PoE39BTCGKjv3Iocf6AFbRP/wZT/kuCxC9QBh9Pu8XPkv/zCZB2mcMg==}
+  '@tailwindcss/oxide-linux-x64-gnu@4.2.4':
+    resolution: {integrity: sha512-7Mx25E4WTfnht0TVRTyC00j3i0M+EeFe7wguMDTlX4mRxafznw0CA8WJkFjWYH5BlgELd1kSjuU2JiPnNZbJDA==}
     engines: {node: '>= 20'}
     cpu: [x64]
     os: [linux]
     libc: [glibc]
 
-  '@tailwindcss/oxide-linux-x64-musl@4.2.2':
-    resolution: {integrity: sha512-XW3t3qwbIwiSyRCggeO2zxe3KWaEbM0/kW9e8+0XpBgyKU4ATYzcVSMKteZJ1iukJ3HgHBjbg9P5YPRCVUxlnQ==}
+  '@tailwindcss/oxide-linux-x64-musl@4.2.4':
+    resolution: {integrity: sha512-2wwJRF7nyhOR0hhHoChc04xngV3iS+akccHTGtz965FwF0up4b2lOdo6kI1EbDaEXKgvcrFBYcYQQ/rrnWFVfA==}
     engines: {node: '>= 20'}
     cpu: [x64]
     os: [linux]
     libc: [musl]
 
-  '@tailwindcss/oxide-wasm32-wasi@4.2.2':
-    resolution: {integrity: sha512-eKSztKsmEsn1O5lJ4ZAfyn41NfG7vzCg496YiGtMDV86jz1q/irhms5O0VrY6ZwTUkFy/EKG3RfWgxSI3VbZ8Q==}
+  '@tailwindcss/oxide-wasm32-wasi@4.2.4':
+    resolution: {integrity: sha512-FQsqApeor8Fo6gUEklzmaa9994orJZZDBAlQpK2Mq+DslRKFJeD6AjHpBQ0kZFQohVr8o85PPh8eOy86VlSCmw==}
     engines: {node: '>=14.0.0'}
     cpu: [wasm32]
     bundledDependencies:
@@ -664,24 +664,24 @@ packages:
       - '@emnapi/wasi-threads'
       - tslib
 
-  '@tailwindcss/oxide-win32-arm64-msvc@4.2.2':
-    resolution: {integrity: sha512-qPmaQM4iKu5mxpsrWZMOZRgZv1tOZpUm+zdhhQP0VhJfyGGO3aUKdbh3gDZc/dPLQwW4eSqWGrrcWNBZWUWaXQ==}
+  '@tailwindcss/oxide-win32-arm64-msvc@4.2.4':
+    resolution: {integrity: sha512-L9BXqxC4ToVgwMFqj3pmZRqyHEztulpUJzCxUtLjobMCzTPsGt1Fa9enKbOpY2iIyVtaHNeNvAK8ERP/64sqGQ==}
     engines: {node: '>= 20'}
     cpu: [arm64]
     os: [win32]
 
-  '@tailwindcss/oxide-win32-x64-msvc@4.2.2':
-    resolution: {integrity: sha512-1T/37VvI7WyH66b+vqHj/cLwnCxt7Qt3WFu5Q8hk65aOvlwAhs7rAp1VkulBJw/N4tMirXjVnylTR72uI0HGcA==}
+  '@tailwindcss/oxide-win32-x64-msvc@4.2.4':
+    resolution: {integrity: sha512-ESlKG0EpVJQwRjXDDa9rLvhEAh0mhP1sF7sap9dNZT0yyl9SAG6T7gdP09EH0vIv0UNTlo6jPWyujD6559fZvw==}
     engines: {node: '>= 20'}
     cpu: [x64]
     os: [win32]
 
-  '@tailwindcss/oxide@4.2.2':
-    resolution: {integrity: sha512-qEUA07+E5kehxYp9BVMpq9E8vnJuBHfJEC0vPC5e7iL/hw7HR61aDKoVoKzrG+QKp56vhNZe4qwkRmMC0zDLvg==}
+  '@tailwindcss/oxide@4.2.4':
+    resolution: {integrity: sha512-9El/iI069DKDSXwTvB9J4BwdO5JhRrOweGaK25taBAvBXyXqJAX+Jqdvs8r8gKpsI/1m0LeJLyQYTf/WLrBT1Q==}
     engines: {node: '>= 20'}
 
-  '@tailwindcss/vite@4.2.2':
-    resolution: {integrity: sha512-mEiF5HO1QqCLXoNEfXVA1Tzo+cYsrqV7w9Juj2wdUFyW07JRenqMG225MvPwr3ZD9N1bFQj46X7r33iHxLUW0w==}
+  '@tailwindcss/vite@4.2.4':
+    resolution: {integrity: sha512-pCvohwOCspk3ZFn6eJzrrX3g4n2JY73H6MmYC87XfGPyTty4YsCjYTMArRZm/zOI8dIt3+EcrLHAFPe5A4bgtw==}
     peerDependencies:
       vite: ^5.2.0 || ^6 || ^7 || ^8
 
@@ -709,8 +709,8 @@ packages:
   '@types/nlcst@2.0.3':
     resolution: {integrity: sha512-vSYNSDe6Ix3q+6Z7ri9lyWqgGhJTmzRjZRqyq15N0Z/1/UnVsno9G/N40NBijoYx2seFDIl0+B2mgAb9mezUCA==}
 
-  '@types/node@24.12.0':
-    resolution: {integrity: sha512-GYDxsZi3ChgmckRT9HPU0WEhKLP08ev/Yfcq2AstjrDASOYCSXeyjDsHg4v5t4jOj7cyDX3vmprafKlWIG9MXQ==}
+  '@types/node@24.12.2':
+    resolution: {integrity: sha512-A1sre26ke7HDIuY/M23nd9gfB+nrmhtYyMINbjI1zHJxYteKR6qSMX56FsmjMcDb3SMcjJg5BiRRgOCC/yBD0g==}
 
   '@types/sax@1.2.7':
     resolution: {integrity: sha512-rO73L89PJxeYM3s3pPPjiPgVVcymqU490g0YO5n5By0k2Erzj6tay/4lr1CHAAU4JyOWd1rpQ8bCf6cZfHU96A==}
@@ -768,8 +768,8 @@ packages:
     resolution: {integrity: sha512-LElXdjswlqjWrPpJFg1Fx4wpkOCxj1TDHlSV4PlaRxHGWko024xICaa97ZkMfs6DRKlCguiAI+rbXv5GWwXIkg==}
     hasBin: true
 
-  astro@6.1.1:
-    resolution: {integrity: sha512-vq8sHpu1JsY1fWAunn+tdKNbVDmLQNiVdyuGsVT2csgITdFGXXVAyEXFWc1DzkMN0ehElPeiHnqItyQOJK+GqA==}
+  astro@6.1.9:
+    resolution: {integrity: sha512-NsAHzMzpznB281g2aM5qnBt2QjfH6ttKiZ3hSZw52If8JJ+62kbnBKbyKhR2glQcJLl7Jfe4GSl0DihFZ36rRQ==}
     engines: {node: '>=22.12.0', npm: '>=9.6.5', pnpm: '>=7.1.0'}
     hasBin: true
 
@@ -824,8 +824,8 @@ packages:
     resolution: {integrity: sha512-dnN3ibLeoRf2HNC+OlCiNc5d2zxbLJXOtiZUudNFSXZrNSydxcCsSpRzXwfu7BBWCIfHPw+xTayeBvJCP/D8Ng==}
     engines: {node: '>= 18'}
 
-  cookie-es@1.2.2:
-    resolution: {integrity: sha512-+W7VmiVINB+ywl1HGXJXmrqkOhpKrIiVZV6tQuV54ZyQC7MMuBt81Vc336GMLoHBq5hV/F9eXgt5Mnx0Rha5Fg==}
+  cookie-es@1.2.3:
+    resolution: {integrity: sha512-lXVyvUvrNXblMqzIRrxHb57UUVmqsSWlxqt3XIjCkUP0wDAf6uicO6KMbEgYrMNtEvWgWHwe42CKxPu9MYAnWw==}
 
   cookie@1.1.1:
     resolution: {integrity: sha512-ei8Aos7ja0weRpFzJnEA9UHJ/7XQmqglbRwnf2ATjcB9Wq874VKH9kfjjirM6UhU2/E5fFYadylyhFldcqSidQ==}
@@ -865,8 +865,8 @@ packages:
   decode-named-character-reference@1.3.0:
     resolution: {integrity: sha512-GtpQYB283KrPp6nRw50q3U9/VfOutZOe103qlN7BPP6Ad27xYnOIWv4lPzo8HCAL+mMZofJ9KEy30fq6MfaK6Q==}
 
-  defu@6.1.4:
-    resolution: {integrity: sha512-mEQCMmwJu317oSz8CwdIOdwf3xMif1ttiM8LTufzc3g6kR+9Pe236twL8j3IYT1F7GfRgGcW6MWxzZjLIkuHIg==}
+  defu@6.1.7:
+    resolution: {integrity: sha512-7z22QmUWiQ/2d0KkdYmANbRUVABpZ9SNYyH5vx6PZ+nE5bcC0l7uFvEfHlyld/HcGBFTL536ClDt3DEcSlEJAQ==}
 
   dequal@2.0.3:
     resolution: {integrity: sha512-0je+qPKHEMohvfRTCEo3CrPG6cAzAYgmzKyxRiYSSDkS6eGJdyVJm7WaYA5ECaAD9wLB2T4EEeymA5aFVcYXCA==}
@@ -879,8 +879,8 @@ packages:
     resolution: {integrity: sha512-Btj2BOOO83o3WyH59e8MgXsxEQVcarkUOpEYrubB0urwnN10yQ364rsiByU11nZlqWYZm05i/of7io4mzihBtQ==}
     engines: {node: '>=8'}
 
-  devalue@5.6.4:
-    resolution: {integrity: sha512-Gp6rDldRsFh/7XuouDbxMH3Mx8GMCcgzIb1pDTvNyn8pZGQ22u+Wa+lGV9dQCltFQ7uVw0MhRyb8XDskNFOReA==}
+  devalue@5.7.1:
+    resolution: {integrity: sha512-MUbZ586EgQqdRnC4yDrlod3BEdyvE4TapGYHMW2CiaW+KkkFmWEFqBUaLltEZCGi0iFXCEjRF0OjF0DV2QHjOA==}
 
   devlop@1.1.0:
     resolution: {integrity: sha512-RWmIqhcFf1lRYBvNmr7qTNuyCt/7/ns2jbpp1+PalgE/rDQcBT0fioSMUpJ93irlUhC5hrg4cYqe6U+0ImW0rA==}
@@ -909,8 +909,8 @@ packages:
     resolution: {integrity: sha512-2QF/g9/zTaPDc3BjNcVTGoBbXBgYfMTTceLaYcFJ/W9kggFUkhxD/hMEeuLKbugyef9SqAx8cpgwlIP/jinUTA==}
     engines: {node: '>=4'}
 
-  enhanced-resolve@5.20.1:
-    resolution: {integrity: sha512-Qohcme7V1inbAfvjItgw0EaxVX5q2rdVEZHRBrEQdRZTssLDGsL8Lwrznl8oQ/6kuTJONLaDcGjkNP247XEhcA==}
+  enhanced-resolve@5.21.0:
+    resolution: {integrity: sha512-otxSQPw4lkOZWkHpB3zaEQs6gWYEsmX4xQF68ElXC/TWvGxGMSGOvoNbaLXm6/cS/fSfHtsEdw90y20PCd+sCA==}
     engines: {node: '>=10.13.0'}
 
   entities@4.5.0:
@@ -921,8 +921,8 @@ packages:
     resolution: {integrity: sha512-aN97NXWF6AWBTahfVOIrB/NShkzi5H7F9r1s9mD3cDj4Ko5f2qhhVoYMibXF7GlLveb/D2ioWay8lxI97Ven3g==}
     engines: {node: '>=0.12'}
 
-  es-module-lexer@2.0.0:
-    resolution: {integrity: sha512-5POEcUuZybH7IdmGsD8wlf0AI55wMecM9rVBTI/qEAy2c1kTOm3DjFYjrBdI2K3BaJjJYfYFeRtM0t9ssnRuxw==}
+  es-module-lexer@2.1.0:
+    resolution: {integrity: sha512-n27zTYMjYu1aj4MjCWzSP7G9r75utsaoc8m61weK+W8JMBGGQybd43GstCXZ3WNmSFtGT9wi59qQTW6mhTR5LQ==}
 
   esast-util-from-estree@2.0.0:
     resolution: {integrity: sha512-4CyanoAudUSBAn5K13H4JhsMH6L9ZP7XbLVe/dKybkxMO7eDyLsT8UHl9TRNrU2Gr9nz+FovfSIjuXWJ81uVwQ==}
@@ -930,8 +930,8 @@ packages:
   esast-util-from-js@2.0.1:
     resolution: {integrity: sha512-8Ja+rNJ0Lt56Pcf3TAmpBZjmx8ZcK5Ts4cAzIOjsjevg9oSXJnl6SUQ2EevU8tv3h6ZLWmoKL5H4fgWvdvfETw==}
 
-  esbuild@0.27.4:
-    resolution: {integrity: sha512-Rq4vbHnYkK5fws5NF7MYTU68FPRE1ajX7heQ/8QXXWqNgqqJ/GkmmyxIzUnf2Sr/bakf8l54716CcMGHYhMrrQ==}
+  esbuild@0.27.7:
+    resolution: {integrity: sha512-IxpibTjyVnmrIQo5aqNpCgoACA/dTKLTlhMHihVHhdkxKyPO1uBBthumT0rdHmcsk9uMonIWS0m4FljWzILh3w==}
     engines: {node: '>=18'}
     hasBin: true
 
@@ -969,6 +969,15 @@ packages:
   extend@3.0.2:
     resolution: {integrity: sha512-fjquC59cD7CyW6urNXK0FBufkZcoiGG80wTuPujX590cB5Ttln20E2UB4S/WARVqhXffZl2LNgS+gQdPIIim/g==}
 
+  fast-string-truncated-width@1.2.1:
+    resolution: {integrity: sha512-Q9acT/+Uu3GwGj+5w/zsGuQjh9O1TyywhIwAxHudtWrgF09nHOPrvTLhQevPbttcxjr/SNN7mJmfOw/B1bXgow==}
+
+  fast-string-width@1.1.0:
+    resolution: {integrity: sha512-O3fwIVIH5gKB38QNbdg+3760ZmGz0SZMgvwJbA1b2TGXceKE6A2cOlfogh1iw8lr049zPyd7YADHy+B7U4W9bQ==}
+
+  fast-wrap-ansi@0.1.6:
+    resolution: {integrity: sha512-HlUwET7a5gqjURj70D5jl7aC3Zmy4weA1SHUfM0JFI0Ptq987NH2TwbBFLoERhfwk+E+eaq4EK3jXoT+R3yp3w==}
+
   fdir@6.5.0:
     resolution: {integrity: sha512-tIbYtZbucOs0BRGqPJkshJUYdL+SDH7dVM8gjy+ERp3WAUjLEFJE+02kanyHtwjWOnwrKYBiwAmM0p4kLJAnXg==}
     engines: {node: '>=12.0.0'}
@@ -1000,8 +1009,8 @@ packages:
   graceful-fs@4.2.11:
     resolution: {integrity: sha512-RbJ5/jmFcNNCcDV5o9eTnBLJ/HszWV0P73bc+Ff4nS/rJj+YaS6IGyiOL0VoBYX+l1Wrl3k63h/KrH+nhJ0XvQ==}
 
-  h3@1.15.10:
-    resolution: {integrity: sha512-YzJeWSkDZxAhvmp8dexjRK5hxziRO7I9m0N53WhvYL5NiWfkUkzssVzY9jvGu0HBoLFW6+duYmNSn6MaZBCCtg==}
+  h3@1.15.11:
+    resolution: {integrity: sha512-L3THSe2MPeBwgIZVSH5zLdBBU90TOxarvhK9d04IDY2AmVS8j2Jz2LIWtwsGOU3lu2I5jCN7FNvVfY2+XyF+mg==}
 
   hast-util-from-html@2.0.3:
     resolution: {integrity: sha512-CUSRHXyKjzHov8yKsQjGOElXy/3EKpyX56ELnkHH34vDVw1N1XSQ1ZcAvTyAPtGqLTuKP/uxM+aLkSPqF/EtMw==}
@@ -1068,6 +1077,11 @@ packages:
     engines: {node: ^12.20.0 || ^14.13.1 || >=16.0.0}
     hasBin: true
 
+  is-docker@4.0.0:
+    resolution: {integrity: sha512-LHE+wROyG/Y/0ZnbktRCoTix2c1RhgWaZraMZ8o1Q7zCh0VSrICJQO5oqIIISrcSBtrXv0o233w1IYwsWCjTzA==}
+    engines: {node: '>=20'}
+    hasBin: true
+
   is-hexadecimal@2.0.1:
     resolution: {integrity: sha512-DgZQp241c8oO6cA1SbTEWiXeoxV42vlcJxgH+B3hi1AiqqKruZR3ZGF8In3fj4+/y/7rHvlOZLZtgJ/4ttYGZg==}
 
@@ -1169,8 +1183,8 @@ packages:
   longest-streak@3.1.0:
     resolution: {integrity: sha512-9Ri+o0JYgehTaVBBDoMqIl8GXtbWg711O3srftcHhZ0dqnETqLaoIK0x17fUw9rFSlK/0NlsKe0Ahhyl5pXE2g==}
 
-  lru-cache@11.2.7:
-    resolution: {integrity: sha512-aY/R+aEsRelme17KGQa/1ZSIpLpNYYrhcrepKTZgE+W3WM16YMCaPwOHLHsmopZHELU0Ojin1lPVxKR0MihncA==}
+  lru-cache@11.3.5:
+    resolution: {integrity: sha512-NxVFwLAnrd9i7KUBxC4DrUhmgjzOs+1Qm50D3oF1/oL+r1NpZ4gA7xvG0/zJ8evR7zIKn4vLf7qTNduWFtCrRw==}
     engines: {node: 20 || >=22}
 
   magic-string@0.30.21:
@@ -1389,18 +1403,18 @@ packages:
   ohash@2.0.11:
     resolution: {integrity: sha512-RdR9FQrFwNBNXAr4GixM8YaRZRJ5PUWbKYbE5eOsrwAjJW0q2REGcf79oYPsLyskQCZG1PLN+S/K1V00joZAoQ==}
 
-  oniguruma-parser@0.12.1:
-    resolution: {integrity: sha512-8Unqkvk1RYc6yq2WBYRj4hdnsAxVze8i7iPfQr8e4uSP3tRv0rpZcbGUDvxfQQcdwHt/e9PrMvGCsa8OqG9X3w==}
+  oniguruma-parser@0.12.2:
+    resolution: {integrity: sha512-6HVa5oIrgMC6aA6WF6XyyqbhRPJrKR02L20+2+zpDtO5QAzGHAUGw5TKQvwi5vctNnRHkJYmjAhRVQF2EKdTQw==}
 
-  oniguruma-to-es@4.3.5:
-    resolution: {integrity: sha512-Zjygswjpsewa0NLTsiizVuMQZbp0MDyM6lIt66OxsF21npUDlzpHi1Mgb/qhQdkb+dWFTzJmFbEWdvZgRho8eQ==}
+  oniguruma-to-es@4.3.6:
+    resolution: {integrity: sha512-csuQ9x3Yr0cEIs/Zgx/OEt9iBw9vqIunAPQkx19R/fiMq2oGVTgcMqO/V3Ybqefr1TBvosI6jU539ksaBULJyA==}
 
   p-limit@7.3.0:
     resolution: {integrity: sha512-7cIXg/Z0M5WZRblrsOla88S4wAK+zOQQWeBYfV3qJuJXMr+LnbYjaadrFaS0JILfEDPVqHyKnZ1Z/1d6J9VVUw==}
     engines: {node: '>=20'}
 
-  p-queue@9.1.0:
-    resolution: {integrity: sha512-O/ZPaXuQV29uSLbxWBGGZO1mCQXV2BLIwUr59JUU9SoH76mnYvtms7aafH/isNSNGwuEfP6W/4xD0/TJXxrizw==}
+  p-queue@9.1.2:
+    resolution: {integrity: sha512-ktsDOALzTYTWWF1PbkNVg2rOt+HaOaMWJMUnt7T3qf5tvZ1L8dBW3tObzprBcXNMKkwj+yFSLqHso0x+UFcJXw==}
     engines: {node: '>=20'}
 
   p-timeout@7.0.1:
@@ -1433,8 +1447,8 @@ packages:
     resolution: {integrity: sha512-QP88BAKvMam/3NxH6vj2o21R6MjxZUAd6nlwAS/pnGvN9IVLocLHxGYIzFhg6fUQ+5th6P4dv4eW9jX3DSIj7A==}
     engines: {node: '>=12'}
 
-  postcss@8.5.8:
-    resolution: {integrity: sha512-OW/rX8O/jXnm82Ey1k44pObPtdblfiuWnrd8X7GJ7emImCOstunGbXUpp7HdBrFQX6rJzn3sPT397Wp5aCwCHg==}
+  postcss@8.5.10:
+    resolution: {integrity: sha512-pMMHxBOZKFU6HgAZ4eyGnwXF/EvPGGqUr0MnZ5+99485wwW41kW91A4LOGxSHhgugZmSChL5AlElNdwlNgcnLQ==}
     engines: {node: ^10 || ^12 || >=14}
 
   prismjs@1.30.0:
@@ -1520,8 +1534,8 @@ packages:
   retext@9.0.0:
     resolution: {integrity: sha512-sbMDcpHCNjvlheSgMfEcVrZko3cDzdbe1x/e7G66dFp0Ff7Mldvi2uv6JkJQzdRcvLYE8CA8Oe8siQx8ZOgTcA==}
 
-  rollup@4.60.0:
-    resolution: {integrity: sha512-yqjxruMGBQJ2gG4HtjZtAfXArHomazDHoFwFFmZZl0r7Pdo7qCIXKqKHZc8yeoMgzJJ+pO6pEEHa+V7uzWlrAQ==}
+  rollup@4.60.2:
+    resolution: {integrity: sha512-J9qZyW++QK/09NyN/zeO0dG/1GdGfyp9lV8ajHnRVLfo/uFsbji5mHnDgn/qYdUHyCkM2N+8VyspgZclfAh0eQ==}
     engines: {node: '>=18.0.0', npm: '>=8.0.0'}
     hasBin: true
 
@@ -1582,11 +1596,11 @@ packages:
     engines: {node: '>=16'}
     hasBin: true
 
-  tailwindcss@4.2.2:
-    resolution: {integrity: sha512-KWBIxs1Xb6NoLdMVqhbhgwZf2PGBpPEiwOqgI4pFIYbNTfBXiKYyWoTsXgBQ9WFg/OlhnvHaY+AEpW7wSmFo2Q==}
+  tailwindcss@4.2.4:
+    resolution: {integrity: sha512-HhKppgO81FQof5m6TEnuBWCZGgfRAWbaeOaGT00KOy/Pf/j6oUihdvBpA7ltCeAvZpFhW3j0PTclkxsd4IXYDA==}
 
-  tapable@2.3.2:
-    resolution: {integrity: sha512-1MOpMXuhGzGL5TTCZFItxCc0AARf1EZFQkGqMm7ERKj8+Hgr5oLvJOVFcC+lRmR8hCe2S3jC4T5D7Vg/d7/fhA==}
+  tapable@2.3.3:
+    resolution: {integrity: sha512-uxc/zpqFg6x7C8vOE7lh6Lbda8eEL9zmVm/PLeTPBRhh1xCgdWaQ+J1CUieGpIfm2HdtsUpRv+HshiasBMcc6A==}
     engines: {node: '>=6'}
 
   tiny-inflate@1.0.3:
@@ -1596,12 +1610,12 @@ packages:
     resolution: {integrity: sha512-Ae3OVUqifDw0wBriIBS7yVaW44Dp6eSHQcyq4Igc7eN2TJH/2YsicswaW+J/OuMvhpDPOKEgpAZCjkb4hpoyeA==}
     engines: {node: ^16.14.0 || >= 17.3.0}
 
-  tinyexec@1.0.4:
-    resolution: {integrity: sha512-u9r3uZC0bdpGOXtlxUIdwf9pkmvhqJdrVCH9fapQtgy/OeTTMZ1nqH7agtvEfmGui6e1XxjcdrlxvxJvc3sMqw==}
+  tinyexec@1.1.1:
+    resolution: {integrity: sha512-VKS/ZaQhhkKFMANmAOhhXVoIfBXblQxGX1myCQ2faQrfmobMftXeJPcZGp0gS07ocvGJWDLZGyOZDadDBqYIJg==}
     engines: {node: '>=18'}
 
-  tinyglobby@0.2.15:
-    resolution: {integrity: sha512-j2Zq4NyQYG5XMST4cbs02Ak8iJUdxRM0XI5QyxXuZOzKOINmWurp3smXu3y5wDcJrptwpSjgXHzIQxR0omXljQ==}
+  tinyglobby@0.2.16:
+    resolution: {integrity: sha512-pn99VhoACYR8nFHhxqix+uvsbXineAasWm5ojXoN8xEwK5Kd3/TrhNn1wByuD52UxWRLy8pu+kRMniEi6Eq9Zg==}
     engines: {node: '>=12.0.0'}
 
   trim-lines@3.0.1:
@@ -1742,8 +1756,8 @@ packages:
   vfile@6.0.3:
     resolution: {integrity: sha512-KzIbH/9tXat2u30jf+smMwFCsno4wHVdNmzFyL+T/L3UGqqk6JKfVqOFOZEpZSHADH1k40ab6NUIXZq422ov3Q==}
 
-  vite@7.3.1:
-    resolution: {integrity: sha512-w+N7Hifpc3gRjZ63vYBXA56dvvRlNWRczTdmCBBa+CotUzAPf5b7YMdMR/8CQoeYE5LX3W4wj6RYTgonm1b9DA==}
+  vite@7.3.2:
+    resolution: {integrity: sha512-Bby3NOsna2jsjfLVOHKes8sGwgl4TT0E6vvpYgnAYDIF/tie7MRaFthmKuHx1NSXjiTueXH3do80FMQgvEktRg==}
     engines: {node: ^20.19.0 || >=22.12.0}
     hasBin: true
     peerDependencies:
@@ -1782,10 +1796,10 @@ packages:
       yaml:
         optional: true
 
-  vitefu@1.1.2:
-    resolution: {integrity: sha512-zpKATdUbzbsycPFBN71nS2uzBUQiVnFoOrr2rvqv34S1lcAgMKKkjWleLGeiJlZ8lwCXvtWaRn7R3ZC16SYRuw==}
+  vitefu@1.1.3:
+    resolution: {integrity: sha512-ub4okH7Z5KLjb6hDyjqrGXqWtWvoYdU3IGm/NorpgHncKoLTCfRIbvlhBm7r0YstIaQRYlp4yEbFqDcKSzXSSg==}
     peerDependencies:
-      vite: ^3.0.0 || ^4.0.0 || ^5.0.0 || ^6.0.0 || ^7.0.0 || ^8.0.0-beta.0
+      vite: ^3.0.0 || ^4.0.0 || ^5.0.0 || ^6.0.0 || ^7.0.0 || ^8.0.0
     peerDependenciesMeta:
       vite:
         optional: true
@@ -1818,13 +1832,13 @@ snapshots:
 
   '@astrojs/compiler@3.0.1': {}
 
-  '@astrojs/internal-helpers@0.8.0':
+  '@astrojs/internal-helpers@0.9.0':
     dependencies:
       picomatch: 4.0.4
 
-  '@astrojs/markdown-remark@7.1.0':
+  '@astrojs/markdown-remark@7.1.1':
     dependencies:
-      '@astrojs/internal-helpers': 0.8.0
+      '@astrojs/internal-helpers': 0.9.0
       '@astrojs/prism': 4.0.1
       github-slugger: 2.0.0
       hast-util-from-html: 2.0.3
@@ -1848,13 +1862,13 @@ snapshots:
     transitivePeerDependencies:
       - supports-color
 
-  '@astrojs/mdx@5.0.3(astro@6.1.1(@types/node@24.12.0)(@vercel/functions@3.4.3)(jiti@2.6.1)(lightningcss@1.32.0)(rollup@4.60.0))':
+  '@astrojs/mdx@5.0.4(astro@6.1.9(@types/node@24.12.2)(@vercel/functions@3.4.3)(jiti@2.6.1)(lightningcss@1.32.0)(rollup@4.60.2))':
     dependencies:
-      '@astrojs/markdown-remark': 7.1.0
+      '@astrojs/markdown-remark': 7.1.1
       '@mdx-js/mdx': 3.1.1
       acorn: 8.16.0
-      astro: 6.1.1(@types/node@24.12.0)(@vercel/functions@3.4.3)(jiti@2.6.1)(lightningcss@1.32.0)(rollup@4.60.0)
-      es-module-lexer: 2.0.0
+      astro: 6.1.9(@types/node@24.12.2)(@vercel/functions@3.4.3)(jiti@2.6.1)(lightningcss@1.32.0)(rollup@4.60.2)
+      es-module-lexer: 2.1.0
       estree-util-visit: 2.0.0
       hast-util-to-html: 9.0.5
       piccolore: 0.1.3
@@ -1877,17 +1891,14 @@ snapshots:
       stream-replace-string: 2.0.0
       zod: 4.3.6
 
-  '@astrojs/telemetry@3.3.0':
+  '@astrojs/telemetry@3.3.1':
     dependencies:
       ci-info: 4.4.0
-      debug: 4.4.3
       dlv: 1.1.3
       dset: 3.1.4
-      is-docker: 3.0.0
+      is-docker: 4.0.0
       is-wsl: 3.1.1
       which-pm-runs: 1.1.0
-    transitivePeerDependencies:
-      - supports-color
 
   '@babel/helper-string-parser@7.27.1': {}
 
@@ -1906,96 +1917,99 @@ snapshots:
     dependencies:
       fontkitten: 1.0.3
 
-  '@clack/core@1.1.0':
+  '@clack/core@1.2.0':
     dependencies:
+      fast-wrap-ansi: 0.1.6
       sisteransi: 1.0.5
 
-  '@clack/prompts@1.1.0':
+  '@clack/prompts@1.2.0':
     dependencies:
-      '@clack/core': 1.1.0
+      '@clack/core': 1.2.0
+      fast-string-width: 1.1.0
+      fast-wrap-ansi: 0.1.6
       sisteransi: 1.0.5
 
-  '@emnapi/runtime@1.9.1':
+  '@emnapi/runtime@1.10.0':
     dependencies:
       tslib: 2.8.1
     optional: true
 
-  '@esbuild/aix-ppc64@0.27.4':
+  '@esbuild/aix-ppc64@0.27.7':
     optional: true
 
-  '@esbuild/android-arm64@0.27.4':
+  '@esbuild/android-arm64@0.27.7':
     optional: true
 
-  '@esbuild/android-arm@0.27.4':
+  '@esbuild/android-arm@0.27.7':
     optional: true
 
-  '@esbuild/android-x64@0.27.4':
+  '@esbuild/android-x64@0.27.7':
     optional: true
 
-  '@esbuild/darwin-arm64@0.27.4':
+  '@esbuild/darwin-arm64@0.27.7':
     optional: true
 
-  '@esbuild/darwin-x64@0.27.4':
+  '@esbuild/darwin-x64@0.27.7':
     optional: true
 
-  '@esbuild/freebsd-arm64@0.27.4':
+  '@esbuild/freebsd-arm64@0.27.7':
     optional: true
 
-  '@esbuild/freebsd-x64@0.27.4':
+  '@esbuild/freebsd-x64@0.27.7':
     optional: true
 
-  '@esbuild/linux-arm64@0.27.4':
+  '@esbuild/linux-arm64@0.27.7':
     optional: true
 
-  '@esbuild/linux-arm@0.27.4':
+  '@esbuild/linux-arm@0.27.7':
     optional: true
 
-  '@esbuild/linux-ia32@0.27.4':
+  '@esbuild/linux-ia32@0.27.7':
     optional: true
 
-  '@esbuild/linux-loong64@0.27.4':
+  '@esbuild/linux-loong64@0.27.7':
     optional: true
 
-  '@esbuild/linux-mips64el@0.27.4':
+  '@esbuild/linux-mips64el@0.27.7':
     optional: true
 
-  '@esbuild/linux-ppc64@0.27.4':
+  '@esbuild/linux-ppc64@0.27.7':
     optional: true
 
-  '@esbuild/linux-riscv64@0.27.4':
+  '@esbuild/linux-riscv64@0.27.7':
     optional: true
 
-  '@esbuild/linux-s390x@0.27.4':
+  '@esbuild/linux-s390x@0.27.7':
     optional: true
 
-  '@esbuild/linux-x64@0.27.4':
+  '@esbuild/linux-x64@0.27.7':
     optional: true
 
-  '@esbuild/netbsd-arm64@0.27.4':
+  '@esbuild/netbsd-arm64@0.27.7':
     optional: true
 
-  '@esbuild/netbsd-x64@0.27.4':
+  '@esbuild/netbsd-x64@0.27.7':
     optional: true
 
-  '@esbuild/openbsd-arm64@0.27.4':
+  '@esbuild/openbsd-arm64@0.27.7':
     optional: true
 
-  '@esbuild/openbsd-x64@0.27.4':
+  '@esbuild/openbsd-x64@0.27.7':
     optional: true
 
-  '@esbuild/openharmony-arm64@0.27.4':
+  '@esbuild/openharmony-arm64@0.27.7':
     optional: true
 
-  '@esbuild/sunos-x64@0.27.4':
+  '@esbuild/sunos-x64@0.27.7':
     optional: true
 
-  '@esbuild/win32-arm64@0.27.4':
+  '@esbuild/win32-arm64@0.27.7':
     optional: true
 
-  '@esbuild/win32-ia32@0.27.4':
+  '@esbuild/win32-ia32@0.27.7':
     optional: true
 
-  '@esbuild/win32-x64@0.27.4':
+  '@esbuild/win32-x64@0.27.7':
     optional: true
 
   '@img/colour@1.1.0':
@@ -2083,7 +2097,7 @@ snapshots:
 
   '@img/sharp-wasm32@0.34.5':
     dependencies:
-      '@emnapi/runtime': 1.9.1
+      '@emnapi/runtime': 1.10.0
     optional: true
 
   '@img/sharp-win32-arm64@0.34.5':
@@ -2146,87 +2160,87 @@ snapshots:
 
   '@oslojs/encoding@1.1.0': {}
 
-  '@rollup/pluginutils@5.3.0(rollup@4.60.0)':
+  '@rollup/pluginutils@5.3.0(rollup@4.60.2)':
     dependencies:
       '@types/estree': 1.0.8
       estree-walker: 2.0.2
       picomatch: 4.0.4
     optionalDependencies:
-      rollup: 4.60.0
+      rollup: 4.60.2
 
-  '@rollup/rollup-android-arm-eabi@4.60.0':
+  '@rollup/rollup-android-arm-eabi@4.60.2':
     optional: true
 
-  '@rollup/rollup-android-arm64@4.60.0':
+  '@rollup/rollup-android-arm64@4.60.2':
     optional: true
 
-  '@rollup/rollup-darwin-arm64@4.60.0':
+  '@rollup/rollup-darwin-arm64@4.60.2':
     optional: true
 
-  '@rollup/rollup-darwin-x64@4.60.0':
+  '@rollup/rollup-darwin-x64@4.60.2':
     optional: true
 
-  '@rollup/rollup-freebsd-arm64@4.60.0':
+  '@rollup/rollup-freebsd-arm64@4.60.2':
     optional: true
 
-  '@rollup/rollup-freebsd-x64@4.60.0':
+  '@rollup/rollup-freebsd-x64@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-arm-gnueabihf@4.60.0':
+  '@rollup/rollup-linux-arm-gnueabihf@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-arm-musleabihf@4.60.0':
+  '@rollup/rollup-linux-arm-musleabihf@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-arm64-gnu@4.60.0':
+  '@rollup/rollup-linux-arm64-gnu@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-arm64-musl@4.60.0':
+  '@rollup/rollup-linux-arm64-musl@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-loong64-gnu@4.60.0':
+  '@rollup/rollup-linux-loong64-gnu@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-loong64-musl@4.60.0':
+  '@rollup/rollup-linux-loong64-musl@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-ppc64-gnu@4.60.0':
+  '@rollup/rollup-linux-ppc64-gnu@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-ppc64-musl@4.60.0':
+  '@rollup/rollup-linux-ppc64-musl@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-riscv64-gnu@4.60.0':
+  '@rollup/rollup-linux-riscv64-gnu@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-riscv64-musl@4.60.0':
+  '@rollup/rollup-linux-riscv64-musl@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-s390x-gnu@4.60.0':
+  '@rollup/rollup-linux-s390x-gnu@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-x64-gnu@4.60.0':
+  '@rollup/rollup-linux-x64-gnu@4.60.2':
     optional: true
 
-  '@rollup/rollup-linux-x64-musl@4.60.0':
+  '@rollup/rollup-linux-x64-musl@4.60.2':
     optional: true
 
-  '@rollup/rollup-openbsd-x64@4.60.0':
+  '@rollup/rollup-openbsd-x64@4.60.2':
     optional: true
 
-  '@rollup/rollup-openharmony-arm64@4.60.0':
+  '@rollup/rollup-openharmony-arm64@4.60.2':
     optional: true
 
-  '@rollup/rollup-win32-arm64-msvc@4.60.0':
+  '@rollup/rollup-win32-arm64-msvc@4.60.2':
     optional: true
 
-  '@rollup/rollup-win32-ia32-msvc@4.60.0':
+  '@rollup/rollup-win32-ia32-msvc@4.60.2':
     optional: true
 
-  '@rollup/rollup-win32-x64-gnu@4.60.0':
+  '@rollup/rollup-win32-x64-gnu@4.60.2':
     optional: true
 
-  '@rollup/rollup-win32-x64-msvc@4.60.0':
+  '@rollup/rollup-win32-x64-msvc@4.60.2':
     optional: true
 
   '@shikijs/core@4.0.2':
@@ -2241,7 +2255,7 @@ snapshots:
     dependencies:
       '@shikijs/types': 4.0.2
       '@shikijs/vscode-textmate': 10.0.2
-      oniguruma-to-es: 4.3.5
+      oniguruma-to-es: 4.3.6
 
   '@shikijs/engine-oniguruma@4.0.2':
     dependencies:
@@ -2269,73 +2283,73 @@ snapshots:
 
   '@shikijs/vscode-textmate@10.0.2': {}
 
-  '@tailwindcss/node@4.2.2':
+  '@tailwindcss/node@4.2.4':
     dependencies:
       '@jridgewell/remapping': 2.3.5
-      enhanced-resolve: 5.20.1
+      enhanced-resolve: 5.21.0
       jiti: 2.6.1
       lightningcss: 1.32.0
       magic-string: 0.30.21
       source-map-js: 1.2.1
-      tailwindcss: 4.2.2
+      tailwindcss: 4.2.4
 
-  '@tailwindcss/oxide-android-arm64@4.2.2':
+  '@tailwindcss/oxide-android-arm64@4.2.4':
     optional: true
 
-  '@tailwindcss/oxide-darwin-arm64@4.2.2':
+  '@tailwindcss/oxide-darwin-arm64@4.2.4':
     optional: true
 
-  '@tailwindcss/oxide-darwin-x64@4.2.2':
+  '@tailwindcss/oxide-darwin-x64@4.2.4':
     optional: true
 
-  '@tailwindcss/oxide-freebsd-x64@4.2.2':
+  '@tailwindcss/oxide-freebsd-x64@4.2.4':
     optional: true
 
-  '@tailwindcss/oxide-linux-arm-gnueabihf@4.2.2':
+  '@tailwindcss/oxide-linux-arm-gnueabihf@4.2.4':
     optional: true
 
-  '@tailwindcss/oxide-linux-arm64-gnu@4.2.2':
+  '@tailwindcss/oxide-linux-arm64-gnu@4.2.4':
     optional: true
 
-  '@tailwindcss/oxide-linux-arm64-musl@4.2.2':
+  '@tailwindcss/oxide-linux-arm64-musl@4.2.4':
     optional: true
 
-  '@tailwindcss/oxide-linux-x64-gnu@4.2.2':
+  '@tailwindcss/oxide-linux-x64-gnu@4.2.4':
     optional: true
 
-  '@tailwindcss/oxide-linux-x64-musl@4.2.2':
+  '@tailwindcss/oxide-linux-x64-musl@4.2.4':
     optional: true
 
-  '@tailwindcss/oxide-wasm32-wasi@4.2.2':
+  '@tailwindcss/oxide-wasm32-wasi@4.2.4':
     optional: true
 
-  '@tailwindcss/oxide-win32-arm64-msvc@4.2.2':
+  '@tailwindcss/oxide-win32-arm64-msvc@4.2.4':
     optional: true
 
-  '@tailwindcss/oxide-win32-x64-msvc@4.2.2':
+  '@tailwindcss/oxide-win32-x64-msvc@4.2.4':
     optional: true
 
-  '@tailwindcss/oxide@4.2.2':
+  '@tailwindcss/oxide@4.2.4':
     optionalDependencies:
-      '@tailwindcss/oxide-android-arm64': 4.2.2
-      '@tailwindcss/oxide-darwin-arm64': 4.2.2
-      '@tailwindcss/oxide-darwin-x64': 4.2.2
-      '@tailwindcss/oxide-freebsd-x64': 4.2.2
-      '@tailwindcss/oxide-linux-arm-gnueabihf': 4.2.2
-      '@tailwindcss/oxide-linux-arm64-gnu': 4.2.2
-      '@tailwindcss/oxide-linux-arm64-musl': 4.2.2
-      '@tailwindcss/oxide-linux-x64-gnu': 4.2.2
-      '@tailwindcss/oxide-linux-x64-musl': 4.2.2
-      '@tailwindcss/oxide-wasm32-wasi': 4.2.2
-      '@tailwindcss/oxide-win32-arm64-msvc': 4.2.2
-      '@tailwindcss/oxide-win32-x64-msvc': 4.2.2
-
-  '@tailwindcss/vite@4.2.2(vite@7.3.1(@types/node@24.12.0)(jiti@2.6.1)(lightningcss@1.32.0))':
-    dependencies:
-      '@tailwindcss/node': 4.2.2
-      '@tailwindcss/oxide': 4.2.2
-      tailwindcss: 4.2.2
-      vite: 7.3.1(@types/node@24.12.0)(jiti@2.6.1)(lightningcss@1.32.0)
+      '@tailwindcss/oxide-android-arm64': 4.2.4
+      '@tailwindcss/oxide-darwin-arm64': 4.2.4
+      '@tailwindcss/oxide-darwin-x64': 4.2.4
+      '@tailwindcss/oxide-freebsd-x64': 4.2.4
+      '@tailwindcss/oxide-linux-arm-gnueabihf': 4.2.4
+      '@tailwindcss/oxide-linux-arm64-gnu': 4.2.4
+      '@tailwindcss/oxide-linux-arm64-musl': 4.2.4
+      '@tailwindcss/oxide-linux-x64-gnu': 4.2.4
+      '@tailwindcss/oxide-linux-x64-musl': 4.2.4
+      '@tailwindcss/oxide-wasm32-wasi': 4.2.4
+      '@tailwindcss/oxide-win32-arm64-msvc': 4.2.4
+      '@tailwindcss/oxide-win32-x64-msvc': 4.2.4
+
+  '@tailwindcss/vite@4.2.4(vite@7.3.2(@types/node@24.12.2)(jiti@2.6.1)(lightningcss@1.32.0))':
+    dependencies:
+      '@tailwindcss/node': 4.2.4
+      '@tailwindcss/oxide': 4.2.4
+      tailwindcss: 4.2.4
+      vite: 7.3.2(@types/node@24.12.2)(jiti@2.6.1)(lightningcss@1.32.0)
 
   '@types/debug@4.1.13':
     dependencies:
@@ -2363,13 +2377,13 @@ snapshots:
     dependencies:
       '@types/unist': 3.0.3
 
-  '@types/node@24.12.0':
+  '@types/node@24.12.2':
     dependencies:
       undici-types: 7.16.0
 
   '@types/sax@1.2.7':
     dependencies:
-      '@types/node': 24.12.0
+      '@types/node': 24.12.2
 
   '@types/unist@2.0.11': {}
 
@@ -2406,28 +2420,27 @@ snapshots:
 
   astring@1.9.0: {}
 
-  astro@6.1.1(@types/node@24.12.0)(@vercel/functions@3.4.3)(jiti@2.6.1)(lightningcss@1.32.0)(rollup@4.60.0):
+  astro@6.1.9(@types/node@24.12.2)(@vercel/functions@3.4.3)(jiti@2.6.1)(lightningcss@1.32.0)(rollup@4.60.2):
     dependencies:
       '@astrojs/compiler': 3.0.1
-      '@astrojs/internal-helpers': 0.8.0
-      '@astrojs/markdown-remark': 7.1.0
-      '@astrojs/telemetry': 3.3.0
+      '@astrojs/internal-helpers': 0.9.0
+      '@astrojs/markdown-remark': 7.1.1
+      '@astrojs/telemetry': 3.3.1
       '@capsizecss/unpack': 4.0.0
-      '@clack/prompts': 1.1.0
+      '@clack/prompts': 1.2.0
       '@oslojs/encoding': 1.1.0
-      '@rollup/pluginutils': 5.3.0(rollup@4.60.0)
+      '@rollup/pluginutils': 5.3.0(rollup@4.60.2)
       aria-query: 5.3.2
       axobject-query: 4.1.0
       ci-info: 4.4.0
       clsx: 2.1.1
       common-ancestor-path: 2.0.0
       cookie: 1.1.1
-      devalue: 5.6.4
+      devalue: 5.7.1
       diff: 8.0.4
-      dlv: 1.1.3
       dset: 3.1.4
-      es-module-lexer: 2.0.0
-      esbuild: 0.27.4
+      es-module-lexer: 2.1.0
+      esbuild: 0.27.7
       flattie: 1.1.1
       fontace: 0.4.1
       github-slugger: 2.0.0
@@ -2440,7 +2453,7 @@ snapshots:
       neotraverse: 0.6.18
       obug: 2.1.1
       p-limit: 7.3.0
-      p-queue: 9.1.0
+      p-queue: 9.1.2
       package-manager-detector: 1.6.0
       piccolore: 0.1.3
       picomatch: 4.0.4
@@ -2450,16 +2463,16 @@ snapshots:
       smol-toml: 1.6.1
       svgo: 4.0.1
       tinyclip: 0.1.12
-      tinyexec: 1.0.4
-      tinyglobby: 0.2.15
+      tinyexec: 1.1.1
+      tinyglobby: 0.2.16
       tsconfck: 3.1.6
       ultrahtml: 1.6.0
       unifont: 0.7.4
       unist-util-visit: 5.1.0
       unstorage: 1.17.5(@vercel/functions@3.4.3)
       vfile: 6.0.3
-      vite: 7.3.1(@types/node@24.12.0)(jiti@2.6.1)(lightningcss@1.32.0)
-      vitefu: 1.1.2(vite@7.3.1(@types/node@24.12.0)(jiti@2.6.1)(lightningcss@1.32.0))
+      vite: 7.3.2(@types/node@24.12.2)(jiti@2.6.1)(lightningcss@1.32.0)
+      vitefu: 1.1.3(vite@7.3.2(@types/node@24.12.2)(jiti@2.6.1)(lightningcss@1.32.0))
       xxhash-wasm: 1.1.0
       yargs-parser: 22.0.0
       zod: 4.3.6
@@ -2532,7 +2545,7 @@ snapshots:
 
   common-ancestor-path@2.0.0: {}
 
-  cookie-es@1.2.2: {}
+  cookie-es@1.2.3: {}
 
   cookie@1.1.1: {}
 
@@ -2572,7 +2585,7 @@ snapshots:
     dependencies:
       character-entities: 2.0.2
 
-  defu@6.1.4: {}
+  defu@6.1.7: {}
 
   dequal@2.0.3: {}
 
@@ -2580,7 +2593,7 @@ snapshots:
 
   detect-libc@2.1.2: {}
 
-  devalue@5.6.4: {}
+  devalue@5.7.1: {}
 
   devlop@1.1.0:
     dependencies:
@@ -2610,16 +2623,16 @@ snapshots:
 
   dset@3.1.4: {}
 
-  enhanced-resolve@5.20.1:
+  enhanced-resolve@5.21.0:
     dependencies:
       graceful-fs: 4.2.11
-      tapable: 2.3.2
+      tapable: 2.3.3
 
   entities@4.5.0: {}
 
   entities@6.0.1: {}
 
-  es-module-lexer@2.0.0: {}
+  es-module-lexer@2.1.0: {}
 
   esast-util-from-estree@2.0.0:
     dependencies:
@@ -2635,34 +2648,34 @@ snapshots:
       esast-util-from-estree: 2.0.0
       vfile-message: 4.0.3
 
-  esbuild@0.27.4:
+  esbuild@0.27.7:
     optionalDependencies:
-      '@esbuild/aix-ppc64': 0.27.4
-      '@esbuild/android-arm': 0.27.4
-      '@esbuild/android-arm64': 0.27.4
-      '@esbuild/android-x64': 0.27.4
-      '@esbuild/darwin-arm64': 0.27.4
-      '@esbuild/darwin-x64': 0.27.4
-      '@esbuild/freebsd-arm64': 0.27.4
-      '@esbuild/freebsd-x64': 0.27.4
-      '@esbuild/linux-arm': 0.27.4
-      '@esbuild/linux-arm64': 0.27.4
-      '@esbuild/linux-ia32': 0.27.4
-      '@esbuild/linux-loong64': 0.27.4
-      '@esbuild/linux-mips64el': 0.27.4
-      '@esbuild/linux-ppc64': 0.27.4
-      '@esbuild/linux-riscv64': 0.27.4
-      '@esbuild/linux-s390x': 0.27.4
-      '@esbuild/linux-x64': 0.27.4
-      '@esbuild/netbsd-arm64': 0.27.4
-      '@esbuild/netbsd-x64': 0.27.4
-      '@esbuild/openbsd-arm64': 0.27.4
-      '@esbuild/openbsd-x64': 0.27.4
-      '@esbuild/openharmony-arm64': 0.27.4
-      '@esbuild/sunos-x64': 0.27.4
-      '@esbuild/win32-arm64': 0.27.4
-      '@esbuild/win32-ia32': 0.27.4
-      '@esbuild/win32-x64': 0.27.4
+      '@esbuild/aix-ppc64': 0.27.7
+      '@esbuild/android-arm': 0.27.7
+      '@esbuild/android-arm64': 0.27.7
+      '@esbuild/android-x64': 0.27.7
+      '@esbuild/darwin-arm64': 0.27.7
+      '@esbuild/darwin-x64': 0.27.7
+      '@esbuild/freebsd-arm64': 0.27.7
+      '@esbuild/freebsd-x64': 0.27.7
+      '@esbuild/linux-arm': 0.27.7
+      '@esbuild/linux-arm64': 0.27.7
+      '@esbuild/linux-ia32': 0.27.7
+      '@esbuild/linux-loong64': 0.27.7
+      '@esbuild/linux-mips64el': 0.27.7
+      '@esbuild/linux-ppc64': 0.27.7
+      '@esbuild/linux-riscv64': 0.27.7
+      '@esbuild/linux-s390x': 0.27.7
+      '@esbuild/linux-x64': 0.27.7
+      '@esbuild/netbsd-arm64': 0.27.7
+      '@esbuild/netbsd-x64': 0.27.7
+      '@esbuild/openbsd-arm64': 0.27.7
+      '@esbuild/openbsd-x64': 0.27.7
+      '@esbuild/openharmony-arm64': 0.27.7
+      '@esbuild/sunos-x64': 0.27.7
+      '@esbuild/win32-arm64': 0.27.7
+      '@esbuild/win32-ia32': 0.27.7
+      '@esbuild/win32-x64': 0.27.7
 
   escape-string-regexp@5.0.0: {}
 
@@ -2705,6 +2718,16 @@ snapshots:
 
   extend@3.0.2: {}
 
+  fast-string-truncated-width@1.2.1: {}
+
+  fast-string-width@1.1.0:
+    dependencies:
+      fast-string-truncated-width: 1.2.1
+
+  fast-wrap-ansi@0.1.6:
+    dependencies:
+      fast-string-width: 1.1.0
+
   fdir@6.5.0(picomatch@4.0.4):
     optionalDependencies:
       picomatch: 4.0.4
@@ -2726,11 +2749,11 @@ snapshots:
 
   graceful-fs@4.2.11: {}
 
-  h3@1.15.10:
+  h3@1.15.11:
     dependencies:
-      cookie-es: 1.2.2
+      cookie-es: 1.2.3
       crossws: 0.3.5
-      defu: 6.1.4
+      defu: 6.1.7
       destr: 2.0.5
       iron-webcrypto: 1.2.1
       node-mock-http: 1.0.4
@@ -2887,6 +2910,8 @@ snapshots:
 
   is-docker@3.0.0: {}
 
+  is-docker@4.0.0: {}
+
   is-hexadecimal@2.0.1: {}
 
   is-inside-container@1.0.0:
@@ -2956,7 +2981,7 @@ snapshots:
 
   longest-streak@3.1.0: {}
 
-  lru-cache@11.2.7: {}
+  lru-cache@11.3.5: {}
 
   magic-string@0.30.21:
     dependencies:
@@ -3441,11 +3466,11 @@ snapshots:
 
   ohash@2.0.11: {}
 
-  oniguruma-parser@0.12.1: {}
+  oniguruma-parser@0.12.2: {}
 
-  oniguruma-to-es@4.3.5:
+  oniguruma-to-es@4.3.6:
     dependencies:
-      oniguruma-parser: 0.12.1
+      oniguruma-parser: 0.12.2
       regex: 6.1.0
       regex-recursion: 6.0.2
 
@@ -3453,7 +3478,7 @@ snapshots:
     dependencies:
       yocto-queue: 1.2.2
 
-  p-queue@9.1.0:
+  p-queue@9.1.2:
     dependencies:
       eventemitter3: 5.0.4
       p-timeout: 7.0.1
@@ -3493,7 +3518,7 @@ snapshots:
 
   picomatch@4.0.4: {}
 
-  postcss@8.5.8:
+  postcss@8.5.10:
     dependencies:
       nanoid: 3.3.11
       picocolors: 1.1.1
@@ -3652,35 +3677,35 @@ snapshots:
       retext-stringify: 4.0.0
       unified: 11.0.5
 
-  rollup@4.60.0:
+  rollup@4.60.2:
     dependencies:
       '@types/estree': 1.0.8
     optionalDependencies:
-      '@rollup/rollup-android-arm-eabi': 4.60.0
-      '@rollup/rollup-android-arm64': 4.60.0
-      '@rollup/rollup-darwin-arm64': 4.60.0
-      '@rollup/rollup-darwin-x64': 4.60.0
-      '@rollup/rollup-freebsd-arm64': 4.60.0
-      '@rollup/rollup-freebsd-x64': 4.60.0
-      '@rollup/rollup-linux-arm-gnueabihf': 4.60.0
-      '@rollup/rollup-linux-arm-musleabihf': 4.60.0
-      '@rollup/rollup-linux-arm64-gnu': 4.60.0
-      '@rollup/rollup-linux-arm64-musl': 4.60.0
-      '@rollup/rollup-linux-loong64-gnu': 4.60.0
-      '@rollup/rollup-linux-loong64-musl': 4.60.0
-      '@rollup/rollup-linux-ppc64-gnu': 4.60.0
-      '@rollup/rollup-linux-ppc64-musl': 4.60.0
-      '@rollup/rollup-linux-riscv64-gnu': 4.60.0
-      '@rollup/rollup-linux-riscv64-musl': 4.60.0
-      '@rollup/rollup-linux-s390x-gnu': 4.60.0
-      '@rollup/rollup-linux-x64-gnu': 4.60.0
-      '@rollup/rollup-linux-x64-musl': 4.60.0
-      '@rollup/rollup-openbsd-x64': 4.60.0
-      '@rollup/rollup-openharmony-arm64': 4.60.0
-      '@rollup/rollup-win32-arm64-msvc': 4.60.0
-      '@rollup/rollup-win32-ia32-msvc': 4.60.0
-      '@rollup/rollup-win32-x64-gnu': 4.60.0
-      '@rollup/rollup-win32-x64-msvc': 4.60.0
+      '@rollup/rollup-android-arm-eabi': 4.60.2
+      '@rollup/rollup-android-arm64': 4.60.2
+      '@rollup/rollup-darwin-arm64': 4.60.2
+      '@rollup/rollup-darwin-x64': 4.60.2
+      '@rollup/rollup-freebsd-arm64': 4.60.2
+      '@rollup/rollup-freebsd-x64': 4.60.2
+      '@rollup/rollup-linux-arm-gnueabihf': 4.60.2
+      '@rollup/rollup-linux-arm-musleabihf': 4.60.2
+      '@rollup/rollup-linux-arm64-gnu': 4.60.2
+      '@rollup/rollup-linux-arm64-musl': 4.60.2
+      '@rollup/rollup-linux-loong64-gnu': 4.60.2
+      '@rollup/rollup-linux-loong64-musl': 4.60.2
+      '@rollup/rollup-linux-ppc64-gnu': 4.60.2
+      '@rollup/rollup-linux-ppc64-musl': 4.60.2
+      '@rollup/rollup-linux-riscv64-gnu': 4.60.2
+      '@rollup/rollup-linux-riscv64-musl': 4.60.2
+      '@rollup/rollup-linux-s390x-gnu': 4.60.2
+      '@rollup/rollup-linux-x64-gnu': 4.60.2
+      '@rollup/rollup-linux-x64-musl': 4.60.2
+      '@rollup/rollup-openbsd-x64': 4.60.2
+      '@rollup/rollup-openharmony-arm64': 4.60.2
+      '@rollup/rollup-win32-arm64-msvc': 4.60.2
+      '@rollup/rollup-win32-ia32-msvc': 4.60.2
+      '@rollup/rollup-win32-x64-gnu': 4.60.2
+      '@rollup/rollup-win32-x64-msvc': 4.60.2
       fsevents: 2.3.3
 
   sax@1.6.0: {}
@@ -3734,7 +3759,7 @@ snapshots:
 
   sitemap@9.0.1:
     dependencies:
-      '@types/node': 24.12.0
+      '@types/node': 24.12.2
       '@types/sax': 1.2.7
       arg: 5.0.2
       sax: 1.6.0
@@ -3772,17 +3797,17 @@ snapshots:
       picocolors: 1.1.1
       sax: 1.6.0
 
-  tailwindcss@4.2.2: {}
+  tailwindcss@4.2.4: {}
 
-  tapable@2.3.2: {}
+  tapable@2.3.3: {}
 
   tiny-inflate@1.0.3: {}
 
   tinyclip@0.1.12: {}
 
-  tinyexec@1.0.4: {}
+  tinyexec@1.1.1: {}
 
-  tinyglobby@0.2.15:
+  tinyglobby@0.2.16:
     dependencies:
       fdir: 6.5.0(picomatch@4.0.4)
       picomatch: 4.0.4
@@ -3871,8 +3896,8 @@ snapshots:
       anymatch: 3.1.3
       chokidar: 5.0.0
       destr: 2.0.5
-      h3: 1.15.10
-      lru-cache: 11.2.7
+      h3: 1.15.11
+      lru-cache: 11.3.5
       node-fetch-native: 1.6.7
       ofetch: 1.5.1
       ufo: 1.6.3
@@ -3894,23 +3919,23 @@ snapshots:
       '@types/unist': 3.0.3
       vfile-message: 4.0.3
 
-  vite@7.3.1(@types/node@24.12.0)(jiti@2.6.1)(lightningcss@1.32.0):
+  vite@7.3.2(@types/node@24.12.2)(jiti@2.6.1)(lightningcss@1.32.0):
     dependencies:
-      esbuild: 0.27.4
+      esbuild: 0.27.7
       fdir: 6.5.0(picomatch@4.0.4)
       picomatch: 4.0.4
-      postcss: 8.5.8
-      rollup: 4.60.0
-      tinyglobby: 0.2.15
+      postcss: 8.5.10
+      rollup: 4.60.2
+      tinyglobby: 0.2.16
     optionalDependencies:
-      '@types/node': 24.12.0
+      '@types/node': 24.12.2
       fsevents: 2.3.3
       jiti: 2.6.1
       lightningcss: 1.32.0
 
-  vitefu@1.1.2(vite@7.3.1(@types/node@24.12.0)(jiti@2.6.1)(lightningcss@1.32.0)):
+  vitefu@1.1.3(vite@7.3.2(@types/node@24.12.2)(jiti@2.6.1)(lightningcss@1.32.0)):
     optionalDependencies:
-      vite: 7.3.1(@types/node@24.12.0)(jiti@2.6.1)(lightningcss@1.32.0)
+      vite: 7.3.2(@types/node@24.12.2)(jiti@2.6.1)(lightningcss@1.32.0)
 
   web-namespaces@2.0.1: {}
 


---

## unknown

---

## unknown

---

## unknown

---

## unknown

---

## 🤖 Assistant

---

## 🤖 Assistant

## Critical
None.

## Warnings

**Verify advisory scope is fully closed.** The diff bumps the *referenced* versions of `defu`, `vite`, `astro`, and `postcss`, but the lockfile is large and you should confirm no second copy of the vulnerable version remains:

- `defu` 6.1.4 → 6.1.7. The known prototype-pollution advisory (GHSA-2pr6-76vf-7546) is fixed in 6.1.5, so 6.1.7 clears it. Run `pnpm why defu` after install to verify only one resolution exists — `defu` is a common transitive of nitro/h3 ecosystems and pinning slip-ups recur.
- `vite` 7.3.1 → 7.3.2 (single resolution, both as direct astro peer and via `@tailwindcss/vite`). Patch.
- `astro` 6.1.1 → 6.1.9 (8 patch versions). Check Astro's changelog for any behavior changes in routing/SSR shim defaults — none are obvious from the lock alone.
- `postcss` 8.5.8 → 8.5.10. Patch.

**`@astrojs/telemetry` 3.3.0 → 3.3.1 changes its dependency surface.** It dropped `debug` and bumped `is-docker` 3 → 4. `is-docker@4` requires Node ≥20; Astro 6 already requires Node ≥22.12.0, so engines are satisfied. Just flagging because dependency-set shrinkage is the kind of subtle thing that breaks downstream code expecting `debug` namespaces — unlikely to affect a static build but worth a `pnpm build` confirmation.

**New transitive packages introduced** via `@clack/prompts` 1.1.0 → 1.2.0: `fast-string-width`, `fast-string-truncated-width`, `fast-wrap-ansi`. These are tiny utility packages from the same author as `tinyexec`; low risk but new attack surface — check that `pnpm install` resolves them from the registry you trust.

## Suggestions

- After applying, run `pnpm install --frozen-lockfile && pnpm dedupe --check` to confirm no duplicates of `defu`, `vite`, `postcss`, or `astro` survive at vulnerable versions.
- Run `pnpm audit --prod` to confirm Dependabot's findings are now empty against the production tree (devDeps don't ship to the static site).
- The package.json `^` ranges still allow further drift. Since this is a private repo feeding a public site, consider this PR sufficient and rely on Dependabot for the next bump rather than tightening ranges to `~`.
- Run `pnpm test && pnpm build` per CLAUDE.md before merging — Astro 6.1.1 → 6.1.9 is the largest jump and is the one most likely to surface a regression.

## Looks Good

- All five `package.json` bumps stay within the existing caret range semantics; the new minimums simply raise the floor to the patched version. No major-version risk.
- Lockfile is internally consistent: every version reference (`astro@6.1.9`, `vite@7.3.2`, `@types/node@24.12.2`, `rollup@4.60.2`, `esbuild@0.27.7`) is updated everywhere, and snapshot blocks renamed in lockstep. No dangling `4.60.0`/`7.3.1`/`6.1.1` references remain.
- The `vitefu` peer-range change (`^8.0.0-beta.0` → `^8.0.0`) is a tightening to released versions only — neutral for this build.
- No new direct dependencies; no peer-dep widening that affects you; no engines bumps that exceed Astro 6's existing Node ≥22.12.0 floor.
- `@astrojs/mdx@5.0.4` and `@astrojs/sitemap@3.7.2` are both single-patch bumps with no API surface change.
- Diff is purely dependency-audit scope — no source changes mixed in, which is the right shape for a Dependabot-style PR.

---

## unknown

---

## 👤 User

Stop hook feedback:
Auto-compound check: detected compoundable signals [recovery,version-bump] (weight 4) in this turn. Evaluate whether the work just completed contains non-trivial problem-solving worth documenting. If YES (multiple investigation steps, non-obvious solution, or reusable insight): briefly tell the user what you are documenting (one sentence), then immediately run /clavain:compound using the Skill tool. If NO (trivial fix, routine commit, or already documented), say nothing and stop.

---

## unknown

---

## 🤖 Assistant

Nothing worth compounding — this was a read-only review of a routine Dependabot-style version bump, no problem-solving or non-obvious insight produced.

---

## unknown

---

## unknown

---

