import type { ReactNode } from "react";

export function Shelf({
  title,
  action,
  children,
}: {
  title: string;
  action?: ReactNode;
  children: ReactNode;
}) {
  return (
    <section className="space-y-3">
      <div className="flex items-center justify-between px-4">
        <h2 className="text-lg font-bold font-display">{title}</h2>
        {action}
      </div>
      <div className="no-scrollbar flex gap-4 overflow-x-auto px-4 pb-1">{children}</div>
    </section>
  );
}
