import { render, screen } from '@testing-library/react';
import App from './App';

test('renders Hello World and React! paragraph', () => {
  render(<App />);
  const linkElement = screen.getByText(/Hello World and React!/i);
  expect(linkElement).toBeInTheDocument();
});
