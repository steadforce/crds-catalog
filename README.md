# CRDs Catalog

A catalog of JSON Schemas generated from upstream Kubernetes CRDs. This repo automates fetching CRDs from popular projects with the help of Renovate, generating JSON Schemas, and publishing them to be used by tools such as `kubeconform`.

This project serves the same purpose as [datreeio/CRDs-catalog](https://github.com/datreeio/CRDs-catalog), but focuses on automated updates to avoid failing build pipelines due to outdated schemas.

## Goals
- Track upstream CRD sources and keep generated schemas up-to-date.
- Use Renovate and GitHub Actions workflows to automate updates.
- Provide a simple configuration format for adding/removing CRD sources.

## JSON Schemas
- Generated JSON Schemas live under a predictable directory layout: `<group>/<kind>_<version>.json`

## How to use the schemas

### Kubeconform
```shell
kubeconform \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/steadforce/crds-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```

## Configuration
The `crds-catalog-config.yaml` file defines the upstream repositories containing CRDs and their versions including required information for Renovate to track and generate schemas from.

Example:
```yaml
# crds-catalog-config.yaml
sources:
- name: example-project-crds
  repository: https://github.com/example/example-crds.git
  version: 1.2.3
  files: manifests/crds/*.yaml
  renovate: # Will be used by Renovate custom manager and by workflow to identify source
    datasource: github-tags
    depName: keycloak/keycloak-k8s-resources
```

## Usage
- Inspect or edit `crds-catalog-config.yaml` to add/remove upstreams.
- You can run the update script locally for a specific source.
- Make sure you have the following dependencies installed:
  - `curl`
  - `git`
  - `python3`
  - `yq`
- Run:
  ```shell
  ./update-crds.sh <source-name>
  ```

## Workflow
- Renovate updates versions in `crds-catalog-config.yaml` by using a JSONata custom manager.
- When Renovate opens a PR, a GitHub Actions workflow runs that finds the matching source from the branch name in the config file.
- It runs the update script for that particular source.
- The update script clones the upstream Git repository and checks out the version that is defined in the config file.
- The script then uses [openapi2jsonschema.py from kubeconform](https://github.com/yannh/kubeconform/blob/master/scripts/openapi2jsonschema.py) to convert the CRDs from OpenAPI to JSON schemas.
- Finally, the workflow commits and pushes the new schemas to the Renovate PR branch.
- Renovate is configured to automerge the PR if the workflow ran successfully, thus keeping the catalog up-to-date automatically.
