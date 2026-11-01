# Donation Banner Tests

The Bugzilla 5.2 test runner does not discover tests under extensions. Run
these tests explicitly from the Bugzilla source root:

```sh
prove -v extensions/BugzillaDonationBanner/t/*.t
```

Run the command in an environment with Bugzilla's Perl dependencies available.