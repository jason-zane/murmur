export function AccountIdentity({ email }: { email: string }) {
  return (
    <div className="account-identity">
      <span className="account-avatar" aria-hidden="true">
        {email[0]?.toUpperCase() || "V"}
      </span>
      <div>
        <span className="account-label">Signed in as</span>
        <strong className="account-address">{email}</strong>
      </div>
    </div>
  );
}
