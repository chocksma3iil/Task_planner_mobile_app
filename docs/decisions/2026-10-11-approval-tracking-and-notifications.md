# Approval Tracking and Email Notifications

- Date: 2026-10-11
- Status: approved (feature) / proposed (delivery mechanism)
- Context: the owner asked to record which project owner approved each user, and to add email notifications for signup, approval, and assignment events.
- Decision: `assignees.approved_by` stores the confirming owner's id (null until confirmed). Notifications cover a new sign-up (to the project owner), approval or rejection (to the user), and a new task assignment (to the assignee).
- Delivery: proposed through the device's email app; needs connectivity when sending. Automatic sending without user action would need a backend and is deferred.
- Reverses: nothing; extends the local-auth decision of the same date.
- Still open: exact event set; backend mailer if ever approved; first-admin bootstrap and password recovery (see the local-auth record).
