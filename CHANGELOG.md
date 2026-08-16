# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims to follow
[Semantic Versioning](https://semver.org/).

## [0.1.5](https://github.com/bbjansen/simpleton/compare/v0.1.4...v0.1.5) (2026-08-16)


### Features

* **amqp-panel:** New Queue/Exchange/Binding sheets, delete actions, Bindings & Nodes sections ([c2a8834](https://github.com/bbjansen/simpleton/commit/c2a8834fc4dc47d840c2c9ef0d0701a78c3558c2))
* **amqp:** add RabbitMQ management panel and connection editor ([fb6936a](https://github.com/bbjansen/simpleton/commit/fb6936ac8764a2e9ce2f0ebc06b326382b9b3c71))
* **amqp:** add SimpletonAMQP management backend over URLSession ([811a75b](https://github.com/bbjansen/simpleton/commit/811a75bddb9a1d848b547ca87d264fc5c3638e9d))
* **amqp:** policies (TTL/DLX for existing queues), bindings graph, node metrics history ([b335d66](https://github.com/bbjansen/simpleton/commit/b335d668d58c3cd0f68264e7eb369890947d0b1b))
* **amqp:** policies API, bindings-graph layout, node metrics history backend ([23201f3](https://github.com/bbjansen/simpleton/commit/23201f3ea7f31e4cad4aa18a3c1663f057bb8ab6))
* **amqp:** Policies, Graph and node metrics charts in the AMQP panel ([349b555](https://github.com/bbjansen/simpleton/commit/349b555d22dba3e0c85ca241e21c0793cac0e70a))
* **amqp:** queue/exchange creation, bindings, nodes, TTL/DLX ([efb44cb](https://github.com/bbjansen/simpleton/commit/efb44cb6edc20b42bd7e932d7c8d9c912077d290))
* **amqp:** queue/exchange/binding management + per-node metrics ([fff5553](https://github.com/bbjansen/simpleton/commit/fff5553d18a7546caa019f98a29bc9be318d9947))
* **amqp:** RabbitMQ management client panel ([bb6b6a6](https://github.com/bbjansen/simpleton/commit/bb6b6a6fad01467290f25f21130f1d8a2e7f08db))
* client workbench — native SQL client, connection manager, dockable panels, results grid ([58cc85e](https://github.com/bbjansen/simpleton/commit/58cc85e7f58fc2ed4e264e73d837506b797ae702))
* **connections:** add color palette, launch seam, and connection editor ([1da960b](https://github.com/bbjansen/simpleton/commit/1da960bc66d7e1947225ff4d0f64b11014f5ff1b))
* **connections:** add color, group, and tunnel-reference fields ([9d392c9](https://github.com/bbjansen/simpleton/commit/9d392c9d5554ad5bb4af19ea0fe98a9571a31d32))
* **connections:** add ConnectionStore.groups() and byGroup(_:) ([231e3ef](https://github.com/bbjansen/simpleton/commit/231e3ef4f998f21de378886e85ef9a6ae0eb74da))
* **connections:** add Data Connections manager panel ([fff9abe](https://github.com/bbjansen/simpleton/commit/fff9abeccdec55bcc41ab070ce8ad280d9105456))
* **connections:** register Data Connections panel and wire GUI launch to SQL ([1b345e6](https://github.com/bbjansen/simpleton/commit/1b345e637e85ef5a61d85e44940c075b38c92ff7))
* **panels:** add bottom edge-dockable drawer slot hosting a GUI panel ([03e12ed](https://github.com/bbjansen/simpleton/commit/03e12ed4cb404c62a71804031fd3285021dc20a6))
* **panels:** add drawer slot + DockEdge + Equatable to PanelProfile; dedupe profile emissions ([7e9b9a2](https://github.com/bbjansen/simpleton/commit/7e9b9a2f72e53ed4dd13461ec192866bf47e4645))
* **panels:** add hideable tool launcher rail preference ([c145fbc](https://github.com/bbjansen/simpleton/commit/c145fbce781265ccb09e6b247f96c936b68dd222))
* **panels:** add prefersDrawer flag routing launcher clicks to the drawer ([65cb065](https://github.com/bbjansen/simpleton/commit/65cb06585fb4e976e2cc503e8cc7b8792e0fc7ca))
* **panels:** dock the SQL GUI client in the drawer; reveal targets it ([e176d34](https://github.com/bbjansen/simpleton/commit/e176d3441115ee284d0e8e42388a3fba29231ff9))
* **panes:** add .client connection type and startClient (CLI over env creds) ([4c709b5](https://github.com/bbjansen/simpleton/commit/4c709b5beadb8775fd232ae2d0a0771bcbfea218))
* **panes:** drag a data connection into the terminal to open a CLI client pane ([4d035b8](https://github.com/bbjansen/simpleton/commit/4d035b8ed530f53dbf66c9cebb1761f804800061))
* **profiles:** make built-in profiles editable with Reset to Default ([281e49a](https://github.com/bbjansen/simpleton/commit/281e49a1f9c9ca357bd87377dce80db200bd60a6))
* **profiles:** persist all profiles + active selection via ProfilesStore ([64785b3](https://github.com/bbjansen/simpleton/commit/64785b3b091673646b8dd20385799e80d7423d10))
* **profiles:** persist runtime layout edits and divider-drag widths ([7354c26](https://github.com/bbjansen/simpleton/commit/7354c2602dffff01458609f4254f05e9211d73d3))
* **s3:** determinate upload progress in the panel ([8a41b73](https://github.com/bbjansen/simpleton/commit/8a41b73b2ba8d750df33689204b20647661e9d03))
* **s3:** multipart upload with streaming progress ([b117a3a](https://github.com/bbjansen/simpleton/commit/b117a3aeb8cd9d405522d1c8161b61cba1ae8775))
* **s3:** object-browser GUI panel + registration + editor fields ([08835a7](https://github.com/bbjansen/simpleton/commit/08835a757d5b43c3d65091cb67bbe6f32d93826c))
* **s3:** S3 object-browser client panel ([a216778](https://github.com/bbjansen/simpleton/commit/a21677839c86d2ce097464c1eb5239756292c5f5))
* **s3:** SimpletonS3 driver library over Soto (S3Backend + SotoS3Backend + factory) ([b54f13a](https://github.com/bbjansen/simpleton/commit/b54f13ac77fdd9059345be8498b9cd500cf7c5e7))
* **s3:** stream file uploads with multipart for large files ([19f9177](https://github.com/bbjansen/simpleton/commit/19f91775ed105056a5160d0e88f9f1b0d50b9852))
* **sftp:** add bcrypt_pbkdf KDF and OpenSSH cipher primitives ([b85c9d8](https://github.com/bbjansen/simpleton/commit/b85c9d8e1970fff0ae34f1442fc4b0226cddf370))
* **sftp:** add SimpletonSFTP library over Citadel 0.12.1 ([c38cb76](https://github.com/bbjansen/simpleton/commit/c38cb768976c4200c7b1f615c8302e983457ae3e))
* **sftp:** decrypt passphrase-protected ECDSA identity files ([91b1135](https://github.com/bbjansen/simpleton/commit/91b113547e048f4d72941db3de365baba96a5bf2))
* **sftp:** ECDSA identity-file auth (P-256/P-384/P-521) ([eda93cd](https://github.com/bbjansen/simpleton/commit/eda93cd81e966908837c47166622135b6e650e32))
* **sftp:** ECDSA identity-file support (P-256/384/521) ([c33ef90](https://github.com/bbjansen/simpleton/commit/c33ef902d21df98eb3fdc920a68cf7b362c86a5f))
* **sftp:** encrypted ECDSA identity files (bcrypt_pbkdf) ([57c5b92](https://github.com/bbjansen/simpleton/commit/57c5b9227f1886b37faff4e4d7973a0a3e47d025))
* **sftp:** SFTP file-browser panel, registration, and editor fields ([3cc88fa](https://github.com/bbjansen/simpleton/commit/3cc88fadd19edff08d64c2b53d394e6cbc66faee))
* **sftp:** SFTP remote file-browser client panel ([7d08fcb](https://github.com/bbjansen/simpleton/commit/7d08fcbd5d23bc5419edffd1c88ba75ead93f45a))
* **sql:** add MySQL driver via MySQLNIO ([27fa96d](https://github.com/bbjansen/simpleton/commit/27fa96d1c56075f7afe05698e26f94832651d983))
* **sql:** add PostgreSQL driver via PostgresNIO ([9d4e08b](https://github.com/bbjansen/simpleton/commit/9d4e08bfd0d9bb82f6888fcdb25fedf7a2f9822d))
* **sql:** add pure CLI-client command builder (env-based credentials) ([22fa320](https://github.com/bbjansen/simpleton/commit/22fa320a80210b9990100d42d2903696895c37ce))
* **sql:** add schema browser and per-connection query history ([2233329](https://github.com/bbjansen/simpleton/commit/2233329b484fa904508d425ef7455324c0b20b21))
* **sql:** add SimpletonSQL target with SQLDriver seam and models ([460bb0b](https://github.com/bbjansen/simpleton/commit/460bb0b543fe48c5829321d7cb1a17431fc22ed1))
* **sql:** add SQL panel shell with connection editor and results grid ([9d9fae9](https://github.com/bbjansen/simpleton/commit/9d9fae93007bae75fe6f1d07c00eb7416f968806))
* **sql:** add SQLite driver and driver factory ([a4b3a71](https://github.com/bbjansen/simpleton/commit/a4b3a711e45835e839602aff420f63f584d94de4))
* **sql:** cell value inspector — double-click to view full value, JSON, or hex ([2583070](https://github.com/bbjansen/simpleton/commit/2583070ae0e27f017d425452d052c1afdc8f315a))
* **sql:** cell-edit primitives — CellCoord, type-aware parsing, tint tokens ([3d37591](https://github.com/bbjansen/simpleton/commit/3d3759123a3bcf22285185c473c46174d4b79c1f))
* **sql:** database switcher (live USE / reconnect) + fix MySQL USE crash ([e284c0f](https://github.com/bbjansen/simpleton/commit/e284c0f35aeaa8590185ca2646684c388c6364f0))
* **sql:** database switcher (live USE / reconnect) + fix MySQL USE crash ([787d735](https://github.com/bbjansen/simpleton/commit/787d73526bd2571e142327c42221882e34494269))
* **sql:** dedicated SQL workspace shell (model-lift + expand-to-window) ([6e9272c](https://github.com/bbjansen/simpleton/commit/6e9272c263e218b3f49934a4f1270594c4be8464))
* **sql:** dedicated SQL workspace shell (sub-project 1) ([133300f](https://github.com/bbjansen/simpleton/commit/133300f9a232e66ad08b9eeff85de257add25a23))
* **sql:** editable detection + commit path in the panel model ([2840446](https://github.com/bbjansen/simpleton/commit/2840446918ac6ac4e2232155c908e0d153ba56a9))
* **sql:** editable-query parser + parameterized UPDATE builder ([783de5e](https://github.com/bbjansen/simpleton/commit/783de5e902abe2d1df69552f678bc936a7ca0774))
* **sql:** export results to CSV / JSON (copy or save) ([574a984](https://github.com/bbjansen/simpleton/commit/574a9841376a39532b92712382629041f8e6cee4))
* **sql:** export results to CSV / JSON (copy or save) ([4511806](https://github.com/bbjansen/simpleton/commit/45118065930f9f7223fd73e669f47cf8c46f355e))
* **sql:** foreign-key navigation + full frozen first data column ([424350e](https://github.com/bbjansen/simpleton/commit/424350eeb51eb46d00b6b5d7ec4a8e6f97aa882d))
* **sql:** foreign-key navigation from a result cell ([d7b99c8](https://github.com/bbjansen/simpleton/commit/d7b99c87c68a5cf0bf1af5fc546504ae75546603))
* **sql:** freeze the first data column alongside the gutter ([edb806c](https://github.com/bbjansen/simpleton/commit/edb806ce9962cdb2d97a22294d68726931e1c11d))
* **sql:** freeze the row-number gutter during horizontal scroll ([34e8122](https://github.com/bbjansen/simpleton/commit/34e8122c6661baa7f157b5bf45a7d0a28339c1a0))
* **sql:** grid column-order persistence + colored enum pills ([b4f3adc](https://github.com/bbjansen/simpleton/commit/b4f3adc3525e6c4afde864a7c02a8992d61a5b50))
* **sql:** grid pagination, cell-range selection, frozen gutter ([aa77a4d](https://github.com/bbjansen/simpleton/commit/aa77a4d77d71807dc13c3a0009e7327e41d80adc))
* **sql:** inline cell editing for single-table results ([0c9c4f7](https://github.com/bbjansen/simpleton/commit/0c9c4f7a30ad1690650fe4979fccb6c5e459cce2))
* **sql:** inline cell editing UI with staged commit bar ([7674963](https://github.com/bbjansen/simpleton/commit/767496345172209658f8db08c15186f88b410405))
* **sql:** multi-column sort (⌥-click adds secondary keys) ([28a5cfc](https://github.com/bbjansen/simpleton/commit/28a5cfc6f436508df66f768917f8be6167b40ff1))
* **sql:** NSTableView-backed results grid (sort, resize, select, copy, themed) ([abf0ce9](https://github.com/bbjansen/simpleton/commit/abf0ce92bd21757b7efe82fe6614aaf1d7e47a04))
* **sql:** paginate the results grid over the sorted order ([8a08927](https://github.com/bbjansen/simpleton/commit/8a08927e296cd5733cd4714609a50a61b867d5a5))
* **sql:** parameterized execute + dialect on the driver seam ([7091d7d](https://github.com/bbjansen/simpleton/commit/7091d7dc7280dc37419f9934e449cdd48d54dc60))
* **sql:** per-statement result tabs for multi-statement scripts ([bb55de6](https://github.com/bbjansen/simpleton/commit/bb55de67ceb87dcd8f83b8e6640a6f75e8b65ee5))
* **sql:** per-statement result tabs for multi-statement scripts ([18d0339](https://github.com/bbjansen/simpleton/commit/18d0339533c712a8a1cc05c1b7fb46f1d9b61ee4))
* **sql:** persist column order + colored pills for enum-like columns ([d0563d4](https://github.com/bbjansen/simpleton/commit/d0563d443444b7670be897a19ca3f7b4f6b75a6d))
* **sql:** persist grid column widths across queries ([d428eb0](https://github.com/bbjansen/simpleton/commit/d428eb0123b6e516fa68397a8d0af9024b5eb0ad))
* **sql:** Postgres schema switching via search_path ([af435be](https://github.com/bbjansen/simpleton/commit/af435be98fd0c3c746d193bbdaa710b06e48941d))
* **sql:** Postgres schema switching via search_path ([f48bc85](https://github.com/bbjansen/simpleton/commit/f48bc856ef3723290575fd18d9a3fc7c4df812a4))
* **sql:** pure cell presentation + type-aware sort comparator ([d853b4e](https://github.com/bbjansen/simpleton/commit/d853b4ecbf9b7549462e8f41c8cca027216e9d89))
* **sql:** pure paging bounds + rectangular TSV helpers ([ea971a1](https://github.com/bbjansen/simpleton/commit/ea971a1c6d2f6278d34b90b543087d2e82791a10))
* **sql:** real query editor — highlighting, line numbers, autocomplete, run-selection ([3a727bb](https://github.com/bbjansen/simpleton/commit/3a727bb168aab5a229670380eb1e350a85bebd69))
* **sql:** real query editor (sub-project 2) ([ac17d23](https://github.com/bbjansen/simpleton/commit/ac17d2307881c61746a8e1f429f2a7e8e0ddbb45))
* **sql:** record/form mode for a single result row ([b7ae5fe](https://github.com/bbjansen/simpleton/commit/b7ae5fe4861fc2a25baff426f36cfdf9bd7991e7))
* **sql:** rectangular cell-range selection with rectangular copy ([85df5c4](https://github.com/bbjansen/simpleton/commit/85df5c4e2e6a95b68dd93b2528b6dbca8e1c68a4))
* **sql:** results view with Grid|Record toggle, density, wired into the SQL panel ([afab5d2](https://github.com/bbjansen/simpleton/commit/afab5d28ecbf22afe2f9f824acb3d28ea0376d57))
* **sql:** results-grid polish — cell inspector, column-width persistence, multi-column sort ([3c66049](https://github.com/bbjansen/simpleton/commit/3c66049db80987c21f8a5c9ace463953fc83ee9b))
* **sql:** saved / favorite queries per connection ([c1da10e](https://github.com/bbjansen/simpleton/commit/c1da10ec116a244dfcc2a675abc1cf5b37bb6086))
* **sql:** saved / favorite queries per connection ([629b5bd](https://github.com/bbjansen/simpleton/commit/629b5bdb72a2e8841abb6644d170e5cb2d514c81))
* **sql:** searchable schema tree with column detail + context actions ([a21fc44](https://github.com/bbjansen/simpleton/commit/a21fc443efcc2091e0dd1c497c1ea9aec4a1b15f))
* **sql:** searchable schema tree with column detail + context actions ([4f4e116](https://github.com/bbjansen/simpleton/commit/4f4e116e64ac4427df1f9dafba266a4eab3ea93b))
* **sql:** show row count + query time after each run ([9963771](https://github.com/bbjansen/simpleton/commit/996377124b8e05da8ff6b4dde1c1655f8643ff34))
* **sql:** show row count + query time after each run ([500902d](https://github.com/bbjansen/simpleton/commit/500902de268ccf8312203fee21d3beab7b965561))
* **sql:** SQL tokenizer for editor syntax highlighting ([5768fd9](https://github.com/bbjansen/simpleton/commit/5768fd986a1fe64a286262915b0f81491e5690fe))
* **sql:** SQLGridData — in-memory sort order, cell lookup, TSV export ([3ef0281](https://github.com/bbjansen/simpleton/commit/3ef02810b0dd96de263ef304f4373897ecdecefc))
* **sql:** theme the SQL panel/drawer and connection editors with the active appearance ([153a899](https://github.com/bbjansen/simpleton/commit/153a899c9223664671d123862b91ca9ccc9d1017))
* **sql:** themed NSColor + NSFont tokens for the results grid ([b2de65b](https://github.com/bbjansen/simpleton/commit/b2de65bb85dcde4504b8ec17cfc431bd1a5730fa))


### Bug Fixes

* **amqp:** constant auto-refresh interval + invalidate URLSession on teardown ([b0affbb](https://github.com/bbjansen/simpleton/commit/b0affbb23dca21aaad9f97a310b11778794f35be))
* **connections:** reliably reveal SQL panel on launch, fix @StateObject ownership and duplicate credentials ([a9bcf31](https://github.com/bbjansen/simpleton/commit/a9bcf3119d571001b7da8b7e62d2393919c92a10))
* **panels:** persist selected profile + all layout edits; editable default profiles ([7c65d32](https://github.com/bbjansen/simpleton/commit/7c65d329603c7059f691ee1b6ec52f5d091cb6c1))
* **s3:** shut down the AWSClient when connect() fails ([d31e440](https://github.com/bbjansen/simpleton/commit/d31e4409e8a703c8edfe72c0878815d372d148b9))
* **sftp:** close a half-open SSH client when connect() fails ([a0d9b44](https://github.com/bbjansen/simpleton/commit/a0d9b44e0dab3aa717e1cad7cfef2830fa01236f))
* **sql:** address adversarial review of the results grid ([defc201](https://github.com/bbjansen/simpleton/commit/defc2016e640f9278369cbdf2864f63aa6657516))
* **sql:** auto-connect on add/select so selecting a database loads it ([27963d4](https://github.com/bbjansen/simpleton/commit/27963d4914a94e1f6cf63a1a4e1c94eb1278f608))
* **sql:** guard connect() against reentrancy; refine connection reveal ([e692f7e](https://github.com/bbjansen/simpleton/commit/e692f7e44cbbd3a56dc792a3942e7e23ce9af85f))
* **sql:** keep the connection bar reachable for saved connections ([9ac349b](https://github.com/bbjansen/simpleton/commit/9ac349b150d48df681396f27e39091c3deef07e1))
* **workbench:** address adversarial review + empty-database feedback ([6661061](https://github.com/bbjansen/simpleton/commit/666106110815583f18330cd89d4f428ba037d91f))

## [0.1.4](https://github.com/bbjansen/simpleton/compare/v0.1.3...v0.1.4) (2026-08-13)


### Features

* **connections:** add ConnectionStore actor with change notification ([51dc54f](https://github.com/bbjansen/simpleton/commit/51dc54f9192b86be65e4cd09412e6cd327ac68da))
* **connections:** add generic Connection model + kinds + secret ([9c00cb7](https://github.com/bbjansen/simpleton/commit/9c00cb72b882f002535b7296561d3ca19bc1e810))
* **connections:** add Keychain-backed CredentialStore ([a92b872](https://github.com/bbjansen/simpleton/commit/a92b87238826497e7ea51fe077d61857e787ea8f))
* **panels:** add ClientPanelScaffold shared chrome for tool panels ([691bc2b](https://github.com/bbjansen/simpleton/commit/691bc2b59c0bd6d9de3f4e7e6e49593684e5855a))

## [0.1.3](https://github.com/bbjansen/simpleton/compare/v0.1.2...v0.1.3) (2026-08-07)


### Features

* **ai:** surface provider error details (model + message) ([f691c28](https://github.com/bbjansen/simpleton/commit/f691c28b774865a1ebfad7cbbf7b3a3808d749e3))
* **header:** add Slack-style window header ([baac066](https://github.com/bbjansen/simpleton/commit/baac0663ddc7a650605b491599349f8cd15ecda9))
* **header:** collapse the omnibox to a search icon below ~820px width ([622193b](https://github.com/bbjansen/simpleton/commit/622193b1b1b749cb9c90ba9d58adb9ff1c74cb0f))
* **plugins:** open-pane action — launch terminal TUIs in a pane ([943af3e](https://github.com/bbjansen/simpleton/commit/943af3ed26b92b330c41d930bec216eee502a578))
* **prefs:** give the Settings window the app's dissolved-glass chrome ([faca94d](https://github.com/bbjansen/simpleton/commit/faca94dcde30dd533f37582fdc11979ebd267192))
* **sidebar:** remove the search field, pin Add Connection to the bottom ([531f647](https://github.com/bbjansen/simpleton/commit/531f64766ec25209e130e35bec5c558eb16aa471))
* **tabs:** make the active tab clearly focused (accent bar + elevated fill) ([ebb246b](https://github.com/bbjansen/simpleton/commit/ebb246b037da7e989db2bcab013fb375b3a68a10))
* **tabs:** replace native macOS window tabbing with custom in-app tabs ([695e17c](https://github.com/bbjansen/simpleton/commit/695e17c708957b2bcec8956f638f80be60f7b0df))
* **terminal:** extend shell integration to bash (OSC 133) ([#18](https://github.com/bbjansen/simpleton/issues/18)) ([93a052b](https://github.com/bbjansen/simpleton/commit/93a052be6b0fcb5897c94526a9b1215dce9ee57b))
* **terminal:** opt-in zsh shell integration (OSC 133) ([#16](https://github.com/bbjansen/simpleton/issues/16)) ([f13a751](https://github.com/bbjansen/simpleton/commit/f13a751ad92c77b577cc2a64fae32be2ae08fe6c))
* **themes:** add chrome-translucency control (frosted glass) ([9bd2c91](https://github.com/bbjansen/simpleton/commit/9bd2c91c0730b75ee549a6cae8e33a2c020fc182))
* **themes:** add ChromeColors + AppearanceTheme models ([3dd04df](https://github.com/bbjansen/simpleton/commit/3dd04dff6e7db9433c4588163eaa156c807cdc05))
* **themes:** add gradient (mixed-hue) themes — Sunset, Ember, Nebula ([eb6eea1](https://github.com/bbjansen/simpleton/commit/eb6eea1c1cc20fdeeca2458f652d9b20e4ad5e8a))
* **themes:** add six more pop-out themes (Teal, Indigo, Crimson, Magenta, Gold, Slate) ([93f7da9](https://github.com/bbjansen/simpleton/commit/93f7da9bf823e224c586633ae0a8033af1122118))
* **themes:** add ThemePalette with 7 presets (dark/light + 5 colored) ([f38d547](https://github.com/bbjansen/simpleton/commit/f38d5470b72a561722c3904734ea2583fd6931ee))
* **themes:** apply terminal palette from the active theme ([c924c55](https://github.com/bbjansen/simpleton/commit/c924c551c5c062bfee9e4f97c2152aed8d4978a4))
* **themes:** drive DesignTokens chrome + accent from the active theme ([20b5e48](https://github.com/bbjansen/simpleton/commit/20b5e4855df8faec5016b7b960af5e5129879f15))
* **themes:** observe ThemeSettings in remaining chrome panels for live theme switching ([0c5805f](https://github.com/bbjansen/simpleton/commit/0c5805fde753d6b6ae6f81372eae6010b325179f))
* **themes:** replace muted developer palettes with saturated Slack-style pop-out themes ([d0695c9](https://github.com/bbjansen/simpleton/commit/d0695c9a6e2be6339201ccb7d864300e32624336))
* **themes:** resolve active AppearanceTheme in AppTheme + publish on ThemeSettings ([25acbce](https://github.com/bbjansen/simpleton/commit/25acbce7239115ab1677cd9c4aa9e0e59ca46ba0))
* **themes:** theme the Settings forms with the active theme ([af4557f](https://github.com/bbjansen/simpleton/commit/af4557f8de20adb55af519c005d289dc9c9a9fe4))
* **themes:** unified theme picker with conditional accent in Appearance settings ([9abecd8](https://github.com/bbjansen/simpleton/commit/9abecd820a7c38ae322b60cc1c9ea85437f60316))
* **themes:** wire live theme switching through applyConfigToAllPanes ([b675410](https://github.com/bbjansen/simpleton/commit/b6754105789e09b154b750ba79e144fcf99fdd18))
* **ui:** adopt Liquid Glass on macOS 26, gated (P5) ([ec5e8fb](https://github.com/bbjansen/simpleton/commit/ec5e8fb14fb1354ca07cfc927ef4b78efb873375))
* **ui:** flash the pane red on a failed command (P4b, exit-status cue) ([#15](https://github.com/bbjansen/simpleton/issues/15)) ([3c79b66](https://github.com/bbjansen/simpleton/commit/3c79b6605f69476149c543f9c623f5095ae08401))
* **ui:** frosted-glass command palette and quick connect (P3) ([ce44d22](https://github.com/bbjansen/simpleton/commit/ce44d2216b81000f9c67cfa8ea9616a089b3f871))
* **ui:** pane right-click split/close menu + hoist Add Connection to sidebar top ([d8570b8](https://github.com/bbjansen/simpleton/commit/d8570b88fb818414a126d64c12d073ab3562d192))
* **ui:** premium dark redesign + native Dark/Light/Auto theming ([019b0b8](https://github.com/bbjansen/simpleton/commit/019b0b8ef26c0c4c1dbc05a8756c28ecd60b26aa))
* **ui:** snappy motion + hierarchical SF Symbols (P4a) ([aac6fde](https://github.com/bbjansen/simpleton/commit/aac6fde89d6b3f6ad859b475a671e0ee8fcf4049))
* **ui:** system-accent active-pane border + dim inactive panes (P2) ([040cd7a](https://github.com/bbjansen/simpleton/commit/040cd7a3d884224c01f38034c3acd6d850ef44ad))
* **ui:** translucent vibrancy chrome (P1) ([73359c3](https://github.com/bbjansen/simpleton/commit/73359c36fa6fc0a1ba4f994a08137e35a4d093e4))
* **workspaces:** bundle theme/profile/plugins with the layout + apply on open ([2a8c3ce](https://github.com/bbjansen/simpleton/commit/2a8c3ce345403468cfe30cf6ddcdd6185f1bbe31))
* **workspaces:** deeper prefs, replace-mode, defaults, rename/duplicate, auto-sync ([8d99da3](https://github.com/bbjansen/simpleton/commit/8d99da3f15b2fe9cec6af4d38246a21f79ce7579))
* **workspaces:** header switcher + Settings editor for switchable setups ([a8436a8](https://github.com/bbjansen/simpleton/commit/a8436a8933900311d8d1795773b2071d87670211))


### Bug Fixes

* **dialogs:** clean up the command palette + quick connect floating panels ([74678a7](https://github.com/bbjansen/simpleton/commit/74678a7368fc1cece1f1c959336f37e2f2edde8d))
* **header:** ground the header bar + close the top transparent strip ([eb2c67b](https://github.com/bbjansen/simpleton/commit/eb2c67b4f46238f1bb7517aa44116b5c3278f404))
* **header:** vertically center the traffic lights in the 46px header ([23398ea](https://github.com/bbjansen/simpleton/commit/23398ea622da14a29288ae7f6ee30de3391f0a69))
* **keychain:** reliable upsert store, key caching, and silent dev signing ([73e5382](https://github.com/bbjansen/simpleton/commit/73e53827d6da3bd8b8077de429099ac25c4ce15c))
* **palette:** run window-targeting commands against the terminal, not the palette ([918c7ba](https://github.com/bbjansen/simpleton/commit/918c7baace46209d8c4239d9c9aed1deb122d86c))
* **prefs:** apply window opacity and show it as a percentage ([#10](https://github.com/bbjansen/simpleton/issues/10)) ([4582653](https://github.com/bbjansen/simpleton/commit/458265324b337bc4cd18e349a7076187cc8547e1))
* **split:** mount the pane container as the initial root, not the raw terminal ([55a7360](https://github.com/bbjansen/simpleton/commit/55a73608d7217eb0626be1a0d442298c3b0f2134))
* **terminal:** parse OSC 7 file:// CWD into a plain path ([#20](https://github.com/bbjansen/simpleton/issues/20)) ([028bbd7](https://github.com/bbjansen/simpleton/commit/028bbd7afbd4210561641216cfde62a6471861ee))
* **themes:** chrome accent follows the active theme, not a stuck indigo placeholder ([7a1a603](https://github.com/bbjansen/simpleton/commit/7a1a603778aa715b0f1557a77b11803d2b67cc08))
* **themes:** complete live-switch sync + gradient backdrop + mono-font/divider polish ([6228e53](https://github.com/bbjansen/simpleton/commit/6228e534dd1807eca62263d3c92cdbe9981ce44e))
* **themes:** force immediate chrome repaint on theme switch (window.appearance + needsLayout/display + displayIfNeeded) so panels sync without a focus event ([038339a](https://github.com/bbjansen/simpleton/commit/038339a7a1074d1aa3ea3afe830f0a7c653972ce))
* **themes:** high-contrast section headings on the sidebar + panels ([87741d6](https://github.com/bbjansen/simpleton/commit/87741d6737c5fccb1d70324777f217c000cf39a8))
* **themes:** sync all panels on live theme switch ([fae6d9a](https://github.com/bbjansen/simpleton/commit/fae6d9a0e0e29cedfff559b3b405218b3bf5464c))
* **themes:** theme every dock panel so it syncs on a live theme switch ([4aa5946](https://github.com/bbjansen/simpleton/commit/4aa59469a28ffa33d6672992f68670d93bd09478))
* **themes:** theme the side-panel backdrop, Preferences window, and sidebar search field ([6b1c0e9](https://github.com/bbjansen/simpleton/commit/6b1c0e9ac2a7903538c6d76e6c68ca9c34dc0645))
* **themes:** theme-tinted glass chrome so each theme is fully its color (not neutral system material) ([2220b82](https://github.com/bbjansen/simpleton/commit/2220b82a2399cbf4edc47f772a4e3952beb35678))
* **themes:** titlebar + background-tab terminals follow the active theme; fix stale comment ([f4c0020](https://github.com/bbjansen/simpleton/commit/f4c00208e45e34bb0280ab015547d6be4b867a8d))
* **ui:** command palette / quick connect arrow-key + enter navigation ([365b31b](https://github.com/bbjansen/simpleton/commit/365b31bf0d04134965aa90644c5d26e6efba7a44))
* **ui:** command palette & quick connect never opened; dismiss on click-away ([2d6d874](https://github.com/bbjansen/simpleton/commit/2d6d874e1bf254c1e8073fefc11a187777f0164e))
* **ui:** keep windows opaque + legible frosted Material chrome ([af26ca6](https://github.com/bbjansen/simpleton/commit/af26ca68edc0a830c137b4c52fdd7acffa11bd6b))
* **ui:** light-mode consistency across panels + new-tab terminal palette ([38c22e7](https://github.com/bbjansen/simpleton/commit/38c22e7ef1e042cab94818779faf6f898d944b22))
* **ui:** quick connect select now connects (target the main terminal window) ([585b2ba](https://github.com/bbjansen/simpleton/commit/585b2ba741d27177e49c38a1488c7fcea075ea0a))

## [0.1.2](https://github.com/bbjansen/simpleton/compare/v0.1.1...v0.1.2) (2026-08-04)


### Features

* **ai:** provider-agnostic AI with presets and live model selection ([#7](https://github.com/bbjansen/simpleton/issues/7)) ([77df043](https://github.com/bbjansen/simpleton/commit/77df043a3c90307599e343e73cb443d3a6b391de))


### Bug Fixes

* **prefs:** make the Skills list column resizable and wider by default ([7bc8b18](https://github.com/bbjansen/simpleton/commit/7bc8b18111a432a23a44965edba0ac49336ec727))

## [0.1.1] - 2026-08-04

First public alpha.

### Added
- Native macOS terminal built on AppKit + SwiftUI and SwiftTerm.
- Native window tabbing and arbitrarily nested split panes (split right/down, directional focus,
  pane zoom).
- SSH connection bookmarks with frecency ranking, `~/.ssh/config` import, keepalive, and
  auto-reconnect; connection sidebar with search.
- Optional AI copilot: per-tab AI chat, skills, and MCP tool support, gated by a command
  classifier that blocks destructive shell actions.
- Dockable panels: command history, environment, processes, Docker, notes, SSH tunnels, and more.
- Theme discovery, a plugin manager with lifecycle events, and user scripts.
- Resizable Preferences window covering General, Appearance, Terminal, SSH, Keys, Plugins, AI,
  Skills, and Profiles.
- `CoreChecks`, a dependency-free, no-Xcode test runner (250+ checks) plus a CI pipeline.

### Fixed
- Startup crash caused by coordinators initialising after the launch sequence.
- Keychain re-prompting on every launch (migration no longer resets the item ACL).
- SSH connections opening in the first tab instead of the active tab.
- Tab status dot not turning green once an SSH session became interactive.
- AI chat showing the previous tab's conversation.
- Panels reading configuration frozen at first display instead of the current settings.
- Session capture/restore of nested splits, extra tabs, and per-pane working directories.
- Several panel/preferences issues: stale writes, UI freezes, leaks, and an index crash.

### Changed
- Session restore is temporarily disabled while its prompt is reworked to be non-blocking.

[0.1.1]: https://github.com/bbjansen/simpleton/releases/tag/v0.1.1
