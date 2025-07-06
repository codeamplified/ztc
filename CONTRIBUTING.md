# Contributing to Zero Touch Cluster

Thank you for your interest in contributing to Zero Touch Cluster! We welcome contributions from the community and are excited to work with you.

## Getting Started

Zero Touch Cluster is a Kubernetes homelab automation project that helps you deploy production-ready infrastructure with minimal manual intervention. Before contributing, please:

1. Read through the [README.md](README.md) to understand the project goals
2. Review the [CLAUDE.md](CLAUDE.md) for technical details and development guidelines
3. Check existing [issues](../../issues) and [pull requests](../../pulls) to avoid duplicating work

## How to Contribute

### Reporting Issues

- Use the GitHub issue tracker to report bugs or request features
- Search existing issues first to avoid duplicates
- Provide clear descriptions with steps to reproduce bugs
- Include relevant system information (OS, versions, etc.)

### Submitting Changes

1. **Fork the repository** and create a feature branch from `main`
2. **Make your changes** following the project's coding standards
3. **Test your changes** thoroughly using `make lint` and `make validate`
4. **Sign your commits** using the Developer Certificate of Origin (DCO)
5. **Submit a pull request** with a clear description of your changes

## Developer Certificate of Origin (DCO)

To ensure proper licensing and legal clarity, all contributions must be signed with the Developer Certificate of Origin. This is a lightweight alternative to a full Contributor License Agreement (CLA) that maintains the same legal protections while being more contributor-friendly.

### What is DCO?

The DCO is a developer's certification that they have the right to submit their contribution under the project's license. It's the same process used by the Linux kernel and many other major open source projects.

### How to Sign Your Commits

Simply add the `-s` flag when committing:

```bash
git commit -s -m "feat(ansible): add support for custom storage classes"
```

This automatically adds a "Signed-off-by" line to your commit message:

```
feat(ansible): add support for custom storage classes

Signed-off-by: Your Name <your.email@example.com>
```

### DCO Requirements

By signing off on your commits, you certify that:

1. The contribution was created in whole or in part by you and you have the right to submit it under the Apache 2.0 license
2. The contribution is based upon previous work that, to the best of your knowledge, is covered under an appropriate license and you have the right under that license to submit that work with modifications
3. The contribution was provided directly to you by some other person who certified (1) or (2) and you have not modified it
4. You understand and agree that this project and the contribution are public and that a record of the contribution is maintained indefinitely

For the full DCO text, see: https://developercertificate.org/

## Code Standards

### Commit Messages

We use [Conventional Commits](https://www.conventionalcommits.org/) for clear commit history:

```
<type>(<scope>): <subject>

<body>
```

**Types:** `fix`, `feat`, `docs`, `refactor`, `test`, `chore`
**Scopes:** `setup`, `ansible`, `k8s`, `storage`, `monitoring`, `argocd`, `backup`

**Examples:**
- `fix(setup): resolve shell syntax error in setup wizard`
- `feat(monitoring): add Grafana dashboard for storage metrics`
- `docs(adr): add ADR-002 resilient infrastructure automation`

### Code Quality

- Run `make lint` to validate Ansible playbooks and YAML syntax
- Run `make validate` to validate Kubernetes manifests
- Follow existing code patterns and conventions
- Write clear, self-documenting code
- Update documentation for user-facing changes

### Testing

- Test your changes in a local development environment
- Use `make teardown && make setup` for complete testing cycles
- Verify that all monitoring and storage systems work correctly
- Document any new testing procedures

## Development Workflow

1. **Setup Development Environment:**
   ```bash
   git clone https://github.com/yourusername/ztc.git
   cd ztc
   # Follow README setup instructions
   ```

2. **Create Feature Branch:**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make Changes and Test:**
   ```bash
   # Make your changes
   make lint
   make validate
   # Test in development environment
   ```

4. **Commit with DCO:**
   ```bash
   git add .
   git commit -s -m "feat(scope): description of changes"
   ```

5. **Push and Create Pull Request:**
   ```bash
   git push origin feature/your-feature-name
   # Create PR via GitHub interface
   ```

## Future: Contributor License Agreement (CLA)

As Zero Touch Cluster grows and develops a larger community, we plan to implement a more comprehensive Contributor License Agreement (CLA) system. This will provide additional legal protections and enable potential commercial licensing options while maintaining our open source commitment.

**Timeline:** CLA implementation will be considered when the project reaches significant community adoption (estimated 50+ regular contributors or 1000+ GitHub stars).

**Current Contributors:** All DCO-signed contributions will be honored under any future CLA system. Your early contributions will not require re-signing.

**Benefits of Future CLA:**
- Enhanced legal protection for all contributors
- Potential for dual-licensing options
- Greater flexibility for commercial partnerships
- Industry-standard contributor agreements

## Project Structure

Understanding the codebase structure will help you contribute effectively:

```
├── ansible/          # Infrastructure automation
├── kubernetes/       # Kubernetes manifests
│   ├── system/      # Core system components (Helm)
│   ├── argocd-apps/ # GitOps application definitions
│   └── workloads/   # Application templates
├── provisioning/    # USB creation and bootstrap scripts
└── docs/           # Documentation and ADRs
```

## Getting Help

- **Documentation:** Check [CLAUDE.md](CLAUDE.md) for detailed technical guidance
- **Issues:** Search existing GitHub issues or create a new one
- **Discussions:** Use GitHub Discussions for questions and ideas
- **Email:** Contact maintainers for sensitive issues

## License

By contributing to Zero Touch Cluster, you agree that your contributions will be licensed under the [Apache License 2.0](LICENSE).

---

Thank you for helping make Zero Touch Cluster better! Your contributions, whether big or small, are greatly appreciated.