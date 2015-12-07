Minify Python packages

- modify .spec file by
  - build it locally
  - looking for the %files entry which lists %{python_sitelib}
  - rpm -qlp the local build
  - add %exclude %{python_sitelib}/*.../*.py lines
  - create new %files source
  - add %{python_sitelib}/*.../*.py lines
  