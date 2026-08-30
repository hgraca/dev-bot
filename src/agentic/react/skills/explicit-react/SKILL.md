---
name: devbot:explicit-react
description: "React 18+ + Next.js + TypeScript development conventions. Use this skill whenever building, scaffolding, or modifying any React project — covers scaffolding, routing, atomic component design, clean architecture, styling, server vs client code separation, TypeScript rules, and data access patterns. Triggers on 'react', 'nextjs', 'create react app', 'react component', 'react project', or when working in a React codebase — even if they only say 'Next.js'."
---

# Skill: React + Next.js + TypeScript

This skill provides conventions for React 18+, Next.js (App Router), and TypeScript, including:

- Atomic component design (atoms, molecules, organisms, templates)
- Clean architecture (ports/adapters, services, repositories)
- CSS Modules, Tailwind, or styled-components for styling
- Explicit server/client code separation (Next.js App Router)
- Strict TypeScript typing
- Data access patterns (React Query, SWR, or custom hooks)

---

## When to Apply

- Scaffold new Next.js projects
- Create components, routes, or API endpoints
- Add styling (CSS Modules, Tailwind, etc.)
- Structure business logic (ports, adapters, services)
- Write TypeScript in a React context
- Discuss React conventions, patterns, or file placement

---

## Core Principles

- **SSR/SSG First**: Prioritize server-side rendering and static generation for performance and SEO.
- **Minimal Client-Side JS**: Reduce client-side JavaScript through server components and server actions.
- **TypeScript Strict**: Always use `"strict": true` in `tsconfig.json`.
- **Functional & Declarative**: Follow functional and declarative programming patterns.
- **Accessibility**: Ensure semantic HTML and ARIA compliance.
- **Modern React**: Use hooks, server components, and React 18+ features.

---

## Further Rules and Practices

Next to this context skill, also load the following context skills:

- `react`
- `nextjs-structure`
- `react-best-practices`

---

## Scaffolding

### Initial Setup

Run once to create the project:

```bash
npx create-next-app@latest <project-name> --typescript --eslint --tailwind --src-dir --app --import-alias "@/*"
```

Select:

- TypeScript: Yes
- ESLint: Yes
- Tailwind CSS: Yes (or your preferred styling solution)
- `src/` directory: Yes
- App Router: Yes
- Custom import alias: `@/*`

```bash
cd <project-name>
npm install
```

### Project Structure

```
src/
├── app/
│   ├── (auth)/
│   │   ├── login/
│   │   │   ├── page.tsx
│   │   │   └── loading.tsx
│   │   └── register/
│   │       ├── page.tsx
│   │       └── loading.tsx
│   ├── (marketing)/
│   │   ├── about/
│   │   │   └── page.tsx
│   │   ├── contact/
│   │   │   └── page.tsx
│   │   └── layout.tsx
│   ├── api/
│   │   ├── users/
│   │   │   ├── route.ts
│   │   │   └── [id]/
│   │   │       └── route.ts
│   │   └── health/
│   │       └── route.ts
│   ├── blog/
│   │   ├── [slug]/
│   │   │   └── page.tsx
│   │   └── page.tsx
│   ├── dashboard/
│   │   ├── layout.tsx
│   │   ├── page.tsx
│   │   └── settings/
│   │       └── page.tsx
│   ├── error.tsx
│   ├── global-error.tsx
│   ├── layout.tsx
│   ├── loading.tsx
│   └── page.tsx
├── components/
│   ├── atoms/
│   │   ├── Button/
│   │   │   ├── Button.tsx
│   │   │   ├── Button.stories.tsx
│   │   │   ├── Button.test.tsx
│   │   │   └── index.ts
│   │   ├── Input/
│   │   │   ├── Input.tsx
│   │   │   ├── Input.stories.tsx
│   │   │   ├── Input.test.tsx
│   │   │   └── index.ts
│   │   └── index.ts
│   ├── molecules/
│   │   ├── Card/
│   │   │   ├── Card.tsx
│   │   │   ├── Card.stories.tsx
│   │   │   ├── Card.test.tsx
│   │   │   └── index.ts
│   │   ├── Form/
│   │   │   ├── Form.tsx
│   │   │   ├── Form.stories.tsx
│   │   │   ├── Form.test.tsx
│   │   │   └── index.ts
│   │   └── index.ts
│   ├── organisms/
│   │   ├── Header/
│   │   │   ├── Header.tsx
│   │   │   ├── Header.stories.tsx
│   │   │   ├── Header.test.tsx
│   │   │   └── index.ts
│   │   ├── Navbar/
│   │   │   ├── Navbar.tsx
│   │   │   ├── Navbar.stories.tsx
│   │   │   ├── Navbar.test.tsx
│   │   │   └── index.ts
│   │   └── index.ts
│   └── templates/
│       ├── BaseLayout/
│       │   ├── BaseLayout.tsx
│       │   └── index.ts
│       └── index.ts
├── hooks/
│   ├── useCounter/
│   │   ├── useCounter.ts
│   │   └── index.ts
│   ├── useFetch/
│   │   ├── useFetch.ts
│   │   └── index.ts
│   └── index.ts
├── lib/
│   ├── constants/
│   │   └── index.ts
│   ├── utils/
│   │   ├── formatters.ts
│   │   ├── helpers.ts
│   │   └── index.ts
│   └── index.ts
├── modules/
│   ├── user/
│   │   ├── adapters/
│   │   │   ├── ApiUserRepository.ts
│   │   │   └── index.ts
│   │   ├── ports/
│   │   │   ├── UserRepository.ts
│   │   │   └── index.ts
│   │   ├── services/
│   │   │   ├── UserService.ts
│   │   │   └── index.ts
│   │   └── index.ts
│   └── index.ts
├── styles/
│   ├── globals.css
│   ├── theme.ts
│   └── variables.css
├── types/
│   ├── index.ts
│   └── user.ts
├── providers/
│   ├── ThemeProvider/
│   │   ├── ThemeProvider.tsx
│   │   └── index.ts
│   └── index.ts
└── test/
    ├── mocks/
    │   └── handlers.ts
    └── utils/
        └── renderWithProviders.tsx
```

**Key Files:**

- `src/app/globals.css`: Global styles
- `src/app/layout.tsx`: Root layout (metadata, fonts, providers)
- `src/app/page.tsx`: Home page
- `src/components/atoms/Button/Button.tsx`: Example atom component
- `src/modules/user/ports/UserRepository.ts`: Example port
- `src/modules/user/adapters/ApiUserRepository.ts`: Example adapter

**File Placement:**

- Colocate tests, stories, and styles with components.
- Use absolute imports with `@/` alias.

---

## Component Design

### Atomic Design

- **Atoms**: Buttons, inputs, icons

    ```tsx
    // src/components/atoms/Button/Button.tsx
    import { ButtonHTMLAttributes, ReactNode } from "react";

    interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
        children: ReactNode;
        variant?: "primary" | "secondary";
    }

    export const Button = ({ children, variant = "primary", ...props }: ButtonProps) => {
        const baseClasses = "px-4 py-2 rounded font-medium";
        const variantClasses = {
            primary: "bg-blue-500 text-white hover:bg-blue-600",
            secondary: "bg-gray-200 text-gray-800 hover:bg-gray-300",
        };

        return (
            <button className={`${baseClasses} ${variantClasses[variant]}`} {...props}>
                {children}
            </button>
        );
    };
    ```

- **Molecules**: Forms, cards, navbars

    ```tsx
    // src/components/molecules/Card/Card.tsx
    import { ReactNode } from "react";

    interface CardProps {
        children: ReactNode;
        title?: string;
    }

    export const Card = ({ children, title }: CardProps) => {
        return (
            <div className="border rounded-lg p-4 shadow-sm">
                {title && <h3 className="text-xl font-bold mb-2">{title}</h3>}
                {children}
            </div>
        );
    };
    ```

- **Organisms**: Headers, footers, complex sections

    ```tsx
    // src/components/organisms/Header/Header.tsx
    import { Navbar } from "../../molecules/Navbar";

    export const Header = () => {
        return (
            <header className="bg-white shadow">
                <Navbar />
            </header>
        );
    };
    ```

- **Templates**: Page layouts
    ```tsx
    // src/components/templates/BaseLayout/BaseLayout.tsx
    import { Header } from "../../organisms/Header";
    import { Footer } from "../../organisms/Footer";
    import { ReactNode } from "react";

    interface BaseLayoutProps {
        children: ReactNode;
    }

    export const BaseLayout = ({ children }: BaseLayoutProps) => {
        return (
            <div className="flex flex-col min-h-screen">
                <Header />
                <main className="flex-grow">{children}</main>
                <Footer />
            </div>
        );
    };
    ```

**Naming:**

- Use PascalCase for components (`Button.tsx`, `UserCard.tsx`).
- Use kebab-case for files in `app/` (`page.tsx`, `loading.tsx`).

---

## Styling

- **Tailwind CSS**: Utility-first (recommended)

    ```tsx
    // Example of Tailwind usage in a component
    export const Button = () => {
        return <button className="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded">Click</button>;
    };
    ```

- **CSS Modules**: Scoped styles

    ```css
    /* src/components/atoms/Button/Button.module.css */
    .button {
        padding: 0.5rem 1rem;
        border-radius: 0.25rem;
        font-weight: 500;
    }
    ```

    ```tsx
    // src/components/atoms/Button/Button.tsx
    import styles from "./Button.module.css";
    export const Button = () => <button className={styles.button}>Click</button>;
    ```

- **Styled Components**: CSS-in-JS

    ```tsx
    // src/components/atoms/Button/Button.tsx
    import styled from "styled-components";
    export const Button = styled.button`
        padding: 0.5rem 1rem;
        border-radius: 0.25rem;
        font-weight: 500;
        background: ${(props) => props.theme.primary};
        color: white;
    `;
    ```

- **Theme**: Define in `src/styles/theme.ts`
    ```ts
    // src/styles/theme.ts
    export const theme = {
        colors: {
            primary: "#3b82f6",
            secondary: "#6b7280",
        },
    };
    ```

---

## State Management

- **Local State**: Use `useState`, `useReducer`.

    ```tsx
    import { useState } from "react";
    export const Counter = () => {
        const [count, setCount] = useState(0);
        return <button onClick={() => setCount((c) => c + 1)}>Count: {count}</button>;
    };
    ```

- **Global State**: Use **Zustand** or **Redux Toolkit** (for complex state).

    ```ts
    // src/store/useCounterStore.ts
    import { create } from "zustand";
    interface CounterState {
        count: number;
        increment: () => void;
    }
    export const useCounterStore = create<CounterState>((set) => ({
        count: 0,
        increment: () => set((state) => ({ count: state.count + 1 })),
    }));
    ```

- **Server State**: Use **React Query** or **SWR** for data fetching.
    ```tsx
    // src/hooks/useFetch/useFetch.ts
    import { useQuery } from '@tanstack/react-query';
    export const useFetch = <T>(url: string) => {
      return useQuery<T>({
        queryKey: [url],
        queryFn: async () => {
          const res = await fetch(url);
          return res.json();
        },
      });
    };
    ```

---

## Data Fetching

- **Next.js App Router**:
    - Use `async/await` in Server Components.
    - Use `fetch` with Next.js caching and revalidation.
    - Use React Query/SWR for client-side data fetching.

**Example:**

```tsx
// app/page.tsx
async function getData() {
    const res = await fetch("https://api.example.com/data", { next: { revalidate: 3600 } });
    if (!res.ok) throw new Error("Failed to fetch");
    return res.json();
}

export default async function Page() {
    const data = await getData();
    return <div>{data.title}</div>;
}
```

---

## Routing

- **File-based Routing**: Use Next.js App Router (`app/` directory).
- **Dynamic Routes**: `app/blog/[slug]/page.tsx`
- **Route Groups**: `(auth)/login/page.tsx`
- **Parallel Routes**: For conditional UI (e.g., dashboard layouts).
- **Intercepting Routes**: For modals or overlays.

**Example:**

```tsx
// app/blog/[slug]/page.tsx
interface BlogPostPageProps {
    params: { slug: string };
}

export default async function BlogPostPage({ params }: BlogPostPageProps) {
    const post = await fetchPost(params.slug);
    return (
        <article>
            <h1>{post.title}</h1>
            <p>{post.content}</p>
        </article>
    );
}
```

---

## Server/Client Code Separation

- **Server Components**: Default in `app/`. No `useState`, `useEffect`, or browser APIs.
- **Client Components**: Add `'use client'` directive at the top.
- **Server Actions**: Use for mutations (e.g., form submissions).

**Example:**

```tsx
// app/actions.ts
"use server";

export async function createUser(formData: FormData) {
    const name = formData.get("name");
    // Server-side logic
    console.log("Creating user:", name);
}

// app/page.tsx
("use client");

export default function Page() {
    return (
        <form action={createUser}>
            <input type="text" name="name" />
            <button type="submit">Submit</button>
        </form>
    );
}
```

---

## Business Logic

- **Ports/Adapters**: Define interfaces in `modules/` and implement adapters for APIs, databases, etc.
- **Services**: Business logic layer (e.g., `UserService`).
- **Repositories**: Data access layer (e.g., `UserRepository`).

**Example:**

```ts
// modules/user/ports/UserRepository.ts
export interface User {
    id: string;
    name: string;
}

export interface UserRepository {
    findById(id: string): Promise<User>;
    findAll(): Promise<User[]>;
}
```

```ts
// modules/user/adapters/ApiUserRepository.ts
import { UserRepository, User } from "../ports/UserRepository";

export class ApiUserRepository implements UserRepository {
    async findById(id: string): Promise<User> {
        const res = await fetch(`https://api.example.com/users/${id}`);
        return res.json();
    }

    async findAll(): Promise<User[]> {
        const res = await fetch("https://api.example.com/users");
        return res.json();
    }
}
```

```ts
// modules/user/services/UserService.ts
import { UserRepository } from "../ports/UserRepository";

export class UserService {
    constructor(private userRepository: UserRepository) {}

    async getUser(id: string) {
        return this.userRepository.findById(id);
    }
}
```

---

## Implementation Roadmap

1. **Module Definitions**: Entity, port contract, service.
2. **Adapters**: API and DB adapters inside each module.
3. **Style Foundations**: Primitives, themes, tokens.
4. **Next.js Routes**: Serve pages with `app/` directory.
5. **Page Components**: Wire modules to UI.
6. **Atomic Components**: Build atoms, molecules, organisms.
7. **Styling Integration**: Apply Tailwind/CSS Modules.
8. **Input Validation**: Use Zod or Yup at module boundaries.
9. **Deploy**: Use Vercel or Node.js for hosting.

---

## Deployment

- **Vercel**: Recommended for Next.js (zero config).
- **Node.js**: For self-hosting.

```bash
npm install -D @next/env
```

`next.config.js`:

```js
/** @type {import('next').NextConfig} */
const nextConfig = {
    output: "standalone", // For Node.js deployment
};

module.exports = nextConfig;
```

---

## Testing

- **Unit Tests**: Jest + React Testing Library.
- **E2E Tests**: Cypress or Playwright.
- **Performance**: Lighthouse for auditing.
- **Component Tests**: Storybook for visual regression.

**Example:**

```tsx
// src/components/atoms/Button/Button.test.tsx
import { render, screen } from "@testing-library/react";
import { Button } from "./Button";

test("renders button with children", () => {
    render(<Button>Click me</Button>);
    expect(screen.getByText("Click me")).toBeInTheDocument();
});
```

---

## Performance

- Focus on **Web Vitals** (LCP, FID, CLS).
- Use Next.js Image for optimized images.
- Implement code splitting and lazy loading.
- Use dynamic imports for heavy components:
    ```tsx
    import dynamic from "next/dynamic";
    const HeavyComponent = dynamic(() => import("../components/HeavyComponent"), {
        loading: () => <p>Loading...</p>,
    });
    ```

---

## Gotchas

- **Server/Client Split**: Server components cannot use hooks or browser APIs.
- `@/` Alias: Use `@/` for imports from `src/`.
- **TypeScript Strict**: Set at scaffold to avoid refactoring later.
- **Ports Before Adapters**: Define interfaces before implementations.
- **Avoid `any`**: Use `unknown` or proper types.
- **Next.js Caching**: Understand `fetch` caching behavior.
- **Server Actions**: Use for mutations, but validate inputs.
